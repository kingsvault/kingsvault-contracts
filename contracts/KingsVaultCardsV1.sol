// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {VRFConsumerBaseV2, VRFCoordinatorV2Interface} from "./lib/VRFConsumerBaseV2.sol";
import {Metadata} from "./lib/Metadata.sol";
import {Tickets} from "./lib/Tickets.sol";
import {TicketsQueryable} from "./lib/TicketsQueryable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KingsVaultCardsV1
 * @notice This contract represents a set of "Kings Vault" collectible cards with multiple tiers,
 *         purchasable for USDT and granting raffle tickets for potential prizes.
 * @dev Uses upgradeable pattern (Initializable) and integrates with Chainlink VRF for random draws.
 */
contract KingsVaultCardsV1 is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    Metadata,
    VRFConsumerBaseV2,
    ReentrancyGuardTransientUpgradeable,
    Tickets,
    TicketsQueryable
{
    // ──────────────────────────────────────────────────────────────────────
    //                               STORAGE
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Holds the primary state variables of the contract.
    struct StateStorage {
        bool _saleStopped; // If true, the primary sale is closed permanently.
        bool _buybackStarted; // If true, users can sell their cards back to the contract.
        bool _drawStarted; // If true, the lucky draw process has begun.
        bool _winnersAwarded; // If true, winners for the main prize(s) have already been selected.
        address _teamWallet; // Address that receives team funds and rewards.
        address _usdt; // USDT token address (assumed 18 decimals) used for payments.
        uint256 _buyers; // Number of unique buyers who purchased cards.
        uint256 _ticketsForCertificate; // A special cutoff of tickets for certain "certificate" draws (first 1000 buyers).
        uint256 _totalRaised; // Total USDT raised from the primary sale.
        uint256 _totalTeamRewards; // Accumulated team rewards that are not yet claimed.
        uint256 _totalTeamRewardsClaimed; // Amount of team rewards already claimed.
        uint256 _totalRefRewards; // Accumulated referral rewards yet to be claimed.
        uint256 _totalRefRewardsClaimed; // Amount of referral rewards already claimed.
        uint256 _refPercentage; // Referral percentage in basis points (1/10,000).
        uint256[] _prices; // The price in USDT (18 decimals) for each card tier.
        uint256[] _bonusTickets; // Number of bonus raffle tickets granted per tier purchased.
        uint256[] _targets; // Fundraising milestones (18 decimals) that unlock further features.
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.state")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StateStorageLocation =
        0xbc62856e0c02dd21442d34f1898c6a8d302a7437a9cb81bf178895b7cbe27200;

    /**
     * @dev Returns a pointer to the StateStorage struct in storage.
     */
    function _getStateStorage() private pure returns (StateStorage storage $) {
        assembly {
            $.slot := StateStorageLocation
        }
    }

    /// @dev Per-user data, holding their spent amount, referrer, and unclaimed referral rewards.
    struct UserData {
        uint256 _spent; // Total USDT spent on buying cards.
        address _referrer; // Address that referred this user.
        uint256 _refRewards; // Accumulated referral rewards not yet claimed.
    }

    /// @dev Holds all mappings for user-related data, including admin/referrer roles.
    struct UsersStorage {
        mapping(address => UserData) _user;
        mapping(address => bool) _admin;
        mapping(address => bool) _referrer;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.users")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UsersStorageLocation =
        0xbb2ab92c0b02289376da8cc9149aca642b578a5fcf5bd499c2b16904c1464200;

    /**
     * @dev Returns a pointer to the UsersStorage struct in storage.
     */
    function _getUsersStorage() private pure returns (UsersStorage storage $) {
        assembly {
            $.slot := UsersStorageLocation
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    //                                EVENTS
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev Emitted when the team wallet address changes from `prev` to `next`.
     */
    event TeamWalletChanged(address indexed prev, address indexed next);

    /**
     * @dev Emitted when an admin is added or removed.
     */
    event AdminChanged(address indexed admin, bool indexed status);

    /**
     * @dev Emitted when a referrer is added or removed.
     */
    event ReferrerChanged(address indexed referrer, bool indexed status);

    /**
     * @dev Emitted once the primary sale is permanently closed.
     */
    event SaleStopped();

    /**
     * @dev Emitted when the buyback feature is started (cannot be undone).
     */
    event BuybackStarted();

    /**
     * @dev Emitted when the lucky draw is started.
     */
    event DrawStarted();

    /**
     * @dev Emitted when peer-to-peer trading is enabled (unpauses transfers).
     */
    event TradeStarted();

    /**
     * @dev Emitted after a successful purchase of one or more cards, including ticket minting.
     * @param user The address that the cards were minted for.
     * @param tier Tier index (0-3) corresponding to the purchased card type.
     * @param quantity The number of cards purchased.
     * @param tickets The number of bonus tickets granted for the purchase.
     */
    event Purchase(
        address indexed user,
        uint256 indexed tier,
        uint256 quantity,
        uint256 tickets
    );

    /**
     * @dev Emitted when referral rewards are accumulated for a referrer due to a user's purchase.
     */
    event RefRewardsAccrued(
        address indexed referrer,
        address indexed user,
        uint256 amount
    );

    /**
     * @dev Emitted when referral rewards are claimed by the referrer.
     */
    event RefRewardsClaimed(address indexed referrer, uint256 amount);

    /**
     * @dev Emitted when team rewards are accumulated from a purchase.
     */
    event TeamRewardsAccrued(
        address indexed team,
        address indexed user,
        uint256 amount
    );

    /**
     * @dev Emitted when the team wallet claims its accumulated rewards.
     */
    event TeamRewardsClaimed(address indexed team, uint256 amount);

    /**
     * @dev Emitted once a winner is selected for a particular token ID (e.g., a prize certificate).
     */
    event Winner(address indexed winner, uint256 indexed tokenId);

    /**
     * @dev Emitted when a prize is redeemed by burning the winning token ID in exchange for USDT.
     */
    event PrizeCashed(
        address indexed winner,
        uint256 indexed tokenId,
        uint256 amount
    );

    /**
     * @dev Emitted when leftover prize funds are withdrawn by the team after winners are awarded.
     */
    event PrizeWithdrawn(address indexed team, uint256 amount);

    /**
     * @dev Emitted when a user sells their card(s) back to the contract under the buyback mechanism.
     */
    event Buyback(address indexed user, uint256 amount);

    // ──────────────────────────────────────────────────────────────────────
    //                              INITIALIZER
    // ──────────────────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Contract initializer (replaces constructor for upgradeable pattern).
     * @dev Sets up the initial state, including pricing, referral percentage, and initial roles.
     * @param initialOwner_    First owner / admin of the contract.
     * @param usdt_            ERC‑20 USDT token address used for payments.
     * @param teamWallet_      Address that will receive funds and hold the main wallet privileges.
     * @param vrfCoordinator_  Chainlink VRF coordinator address.
     */
    function initialize(
        address initialOwner_,
        address usdt_,
        address teamWallet_,
        address vrfCoordinator_
    ) public virtual initializer {
        // -------------------------- OZ initializers ----------------------
        __ERC1155_init("");
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC2981_init();
        __Ownable_init(initialOwner_);
        __Pausable_init();

        // --------------------------- Project libs ------------------------
        __Metadata_init(
            "https://kingsvault.github.io/metadata/",
            "Kings Vault Cards",
            "KVC",
            initialOwner_,
            500
        );
        __Tickets_init();
        __TicketsQueryable_init();
        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_);

        // ---------------------------- Storage ----------------------------
        StateStorage storage state = _getStateStorage();

        state._usdt = usdt_;

        require(teamWallet_ != address(0), "KVC: zero team wallet");
        emit TeamWalletChanged(state._teamWallet, teamWallet_);
        state._teamWallet = teamWallet_;

        // Setting referral percentage to 5% (500 basis points)
        state._refPercentage = 500;

        // Price per card tier (in USDT with 18 decimals)
        state._prices.push(5_000000000000000000);
        state._prices.push(25_000000000000000000);
        state._prices.push(88_000000000000000000);
        state._prices.push(250_000000000000000000);

        // Bonus tickets granted per card purchase for each tier.
        state._bonusTickets.push(5);
        state._bonusTickets.push(35);
        state._bonusTickets.push(150);
        state._bonusTickets.push(500);

        // Funding milestones (18 decimals) at which different contract logic may unlock or change.
        state._targets.push(75_000_000000000000000000);
        state._targets.push(265_000_000000000000000000);
        state._targets.push(350_000_000000000000000000);

        // --------------------------- Admin set‑up ------------------------
        UsersStorage storage uStore = _getUsersStorage();
        uStore._admin[initialOwner_] = true;
        emit AdminChanged(initialOwner_, true);

        // --------------------------- Initial state -----------------------
        // The contract starts paused, which means primary sale & transfers are restricted
        // until the owner calls startTrade() for secondary market or modifies contract state.
        _pause();
    }

    /**
     * @notice Returns the version of the token contract. Useful for upgrades.
     * @return The version string of the contract.
     */
    function version() external view virtual returns (string memory) {
        return "1";
    }

    /**
     * @notice Returns a copy of the contract's StateStorage struct.
     */
    function getState() external pure returns (StateStorage memory) {
        StateStorage memory state = _getStateStorage();
        return state;
    }

    /**
     * @notice Returns various user info (spent amount, referrer, unclaimed refRewards, tickets).
     * @param wallet The address of the user whose info is fetched.
     */
    function getUser(
        address wallet
    )
        external
        view
        returns (
            uint256 _spent,
            address _referrer,
            uint256 _refRewards,
            uint256 _tickets
        )
    {
        UsersStorage storage uStore = _getUsersStorage();
        return (
            uStore._user[wallet]._spent,
            uStore._user[wallet]._referrer,
            uStore._user[wallet]._refRewards,
            ticketsBalanceOf(wallet)
        );
    }

    /**
     * @dev Restricts the function to be called only by an admin or the contract owner.
     */
    modifier onlyAdminOrOwner() {
        address sender = _msgSender();
        UsersStorage storage uStore = _getUsersStorage();
        require(
            uStore._admin[sender] || sender == owner(),
            "KVC: only admin or owner"
        );
        _;
    }

    /**
     * @notice Adds or removes an auxiliary admin. Admins have special privileges like batch buyback or batch claim.
     * @param wallet The address to grant or revoke admin rights.
     * @param status True to grant admin, false to revoke.
     */
    function setAdmin(address wallet, bool status) external onlyOwner {
        UsersStorage storage uStore = _getUsersStorage();
        uStore._admin[wallet] = status;
        emit AdminChanged(wallet, status);
    }

    /**
     * @notice Checks if a given address is an admin.
     * @param wallet The address to query.
     * @return True if the address has admin rights, false otherwise.
     */
    function isAdmin(address wallet) external view returns (bool) {
        UsersStorage storage uStore = _getUsersStorage();
        return uStore._admin[wallet];
    }

    /**
     * @notice Assigns or revokes referral status for a given address.
     * @param wallet The address to grant or revoke referral privileges.
     * @param status True to mark as a referrer, false to revoke.
     */
    function setReferrer(address wallet, bool status) external onlyOwner {
        UsersStorage storage uStore = _getUsersStorage();
        uStore._referrer[wallet] = status;
        emit ReferrerChanged(wallet, status);
    }

    /**
     * @notice Checks if a given address is a registered referrer.
     * @param wallet The address to query.
     * @return True if the address is a referrer, false otherwise.
     */
    function isReferrer(address wallet) external view returns (bool) {
        UsersStorage storage uStore = _getUsersStorage();
        return uStore._referrer[wallet];
    }

    // ========== Sale section ==========

    /**
     * @dev Ensures the primary sale has been stopped.
     */
    modifier thenSaleStopped() {
        StateStorage memory state = _getStateStorage();
        require(state._saleStopped, "KVC: sale must be stopped");
        _;
    }

    /**
     * @dev Ensures the primary sale is still ongoing.
     */
    modifier thenSaleNotStopped() {
        StateStorage memory state = _getStateStorage();
        require(!state._saleStopped, "KVC: sale stopped");
        _;
    }

    /**
     * @notice Permanently closes primary sale for new cards.
     *         Once stopped, it cannot be restarted.
     */
    function stopSale() external thenSaleNotStopped onlyOwner {
        StateStorage storage state = _getStateStorage();
        state._saleStopped = true;
        emit SaleStopped();
    }

    /**
     * @notice Purchases `qty` cards of a specified `tier` for the message sender.
     * @param tier Card tier index (0‑3).
     * @param qty  Number of cards to purchase.
     * @param ref  Optional referrer address. If the user has a referrer set previously, that one is used instead.
     */
    function buy(uint256 tier, uint256 qty, address ref) external {
        _buyTo(_msgSender(), tier, qty, ref);
    }

    /**
     * @notice Purchases `qty` cards for a different address `to`. Payment is pulled from msg.sender.
     * @dev This allows gift purchases or group buys on behalf of another address.
     */
    function buyTo(
        address to,
        uint256 tier,
        uint256 qty,
        address ref
    ) external {
        _buyTo(to, tier, qty, ref);
    }

    /**
     * @dev Internal routine that executes the logic for buying cards:
     *  - Transfers USDT
     *  - Updates user and global sale stats
     *  - Allocates referral and team rewards
     *  - Mints the actual NFTs and bonus tickets
     */
    function _buyTo(
        address to,
        uint256 tier,
        uint256 qty,
        address ref
    ) private nonReentrant thenSaleNotStopped {
        require(tier < 4, "KVC: invalid tier");
        require(qty > 0, "KVC: zero qty");

        StateStorage storage state = _getStateStorage();
        UsersStorage storage uStore = _getUsersStorage();

        // Calculate total cost and pull USDT from buyer
        uint256 cost = state._prices[tier] * qty;
        require(
            IERC20(state._usdt).transferFrom(_msgSender(), address(this), cost),
            "KVC: payment failed"
        );

        // Increment buyer count if this is the user's first purchase
        if (uStore._user[to]._spent == 0) {
            state._buyers++;
        }

        // Update global stats
        state._totalRaised += cost;
        // Handle referral logic
        uint256 refRewards = _doRefRewards(to, ref, cost);
        // Handle team rewards logic
        _doTeamRewards(to, cost, refRewards);
        uStore._user[to]._spent += cost;

        // Mint the requested number of NFTs in the chosen tier
        for (uint256 i = 0; i < qty; i++) {
            _mint(to, _getRandomTokenId(tier), 1, "");
        }

        // Mint the appropriate number of bonus tickets
        uint256 newTickets = state._bonusTickets[tier] * qty;
        _mintTickets(to, newTickets);

        // Track a special cutoff (1000 initial buyers) for an extra certificate draw
        if (state._buyers <= 1000) {
            state._ticketsForCertificate = _ticketsTotal();
        }

        emit Purchase(to, tier, qty, newTickets);
    }

    /**
     * @dev Calculates and logs referral rewards. If a milestone isn't reached yet,
     *      the referrer's rewards remain stored on-chain until a milestone is triggered.
     */
    function _doRefRewards(
        address buyer,
        address ref,
        uint256 cost
    ) private returns (uint256 refRewards) {
        StateStorage storage state = _getStateStorage();
        UsersStorage storage uStore = _getUsersStorage();

        // If user has an existing referrer, override the provided `ref`
        if (uStore._user[buyer]._referrer != address(0)) {
            ref = uStore._user[buyer]._referrer;
        }

        // Check that the referrer is valid and not the buyer themselves
        if (!uStore._referrer[ref] || ref == buyer) {
            return 0;
        }

        // If it's the buyer's first purchase and they have no referrer set, record it.
        if (
            uStore._user[buyer]._spent == 0 &&
            uStore._user[buyer]._referrer == address(0)
        ) {
            uStore._user[buyer]._referrer = ref;
        }

        // Calculate 5% referral reward
        refRewards = (cost * 500) / 10_000;
        state._totalRefRewards += refRewards;

        emit RefRewardsAccrued(ref, buyer, refRewards);

        // If we haven't reached the first milestone, store rewards in user’s account
        if (state._totalRaised < state._targets[0]) {
            uStore._user[ref]._refRewards += refRewards;
            return refRewards;
        }

        // Otherwise, pay out immediately
        uint256 sendAmount = refRewards;
        if (uStore._user[ref]._refRewards > 0) {
            sendAmount += uStore._user[ref]._refRewards;
            uStore._user[ref]._refRewards = 0;
        }

        state._totalRefRewardsClaimed += sendAmount;
        _sendUsdt(ref, sendAmount);
        emit RefRewardsClaimed(ref, sendAmount);

        return refRewards;
    }

    /**
     * @dev Calculates and logs team rewards. Depending on the fundraising milestone,
     *      part of the cost is withheld for the prize pool (car) and some is allocated to the team.
     */
    function _doTeamRewards(
        address buyer,
        uint256 cost,
        uint256 refRewards
    ) private returns (uint256 teamRewards) {
        StateStorage storage state = _getStateStorage();

        address teamWallet = state._teamWallet;

        // If final target isn't reached, team gets 20% minus 5% referral => 15%.
        // If final target was reached mid-transaction, partial calculations are made.
        if (state._totalRaised < state._targets[2]) {
            teamRewards = ((cost * 2_000) / 10_000) - refRewards; // 20% minus referral
        } else if ((state._totalRaised - cost) < state._targets[2]) {
            // If the transaction itself crossed the last milestone boundary, do partial distribution
            uint256 extra = state._totalRaised - state._targets[2];
            uint256 targetDelta = cost - extra;
            teamRewards = ((targetDelta * 2_000) / 10_000) + extra - refRewards;
        } else {
            // Past final target, team effectively gets the full cost minus referral.
            teamRewards = cost - refRewards;
        }

        emit TeamRewardsAccrued(teamWallet, buyer, teamRewards);

        // If we haven't reached the first milestone, store team rewards on contract
        if (state._totalRaised < state._targets[0]) {
            state._totalTeamRewards += teamRewards;
            return teamRewards;
        }

        // Otherwise, pay out immediately
        uint256 sendAmount = teamRewards;
        if (state._totalTeamRewards > 0) {
            sendAmount += state._totalTeamRewards;
            state._totalTeamRewards = 0;
        }

        state._totalTeamRewardsClaimed += sendAmount;
        _sendUsdt(teamWallet, sendAmount);
        emit TeamRewardsClaimed(teamWallet, sendAmount);

        return teamRewards;
    }

    /**
     * @dev Safely sends USDT from this contract to the specified address.
     *      Reverts if the transfer fails.
     */
    function _sendUsdt(address to, uint256 amount) private {
        StateStorage memory state = _getStateStorage();
        require(
            IERC20(state._usdt).transfer(to, amount),
            "KVC: USDT transfer failed"
        );
    }

    /**
     * @dev Generates a pseudo-random card ID based on block attributes, timestamp, and total supply.
     *      Each tier corresponds to 3 potential token IDs within that tier range.
     */
    function _getRandomTokenId(uint256 tier) private view returns (uint256) {
        uint256 baseId = tier * 3 + 1; // Each tier spans 3 token IDs
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    _msgSender(),
                    totalSupply()
                )
            )
        ) % 3; // results in 0, 1, or 2
        return baseId + random;
    }

    /**
     * @dev Determines which token ID corresponds to the "car" or main prize certificate,
     *      based on how much total funding was raised.
     */
    function _getWinnerTokenId() private pure returns (uint256) {
        StateStorage memory state = _getStateStorage();
        if (state._totalRaised >= state._targets[2]) return 16;
        else if (state._totalRaised >= state._targets[1]) return 15;
        else return 14;
    }

    /**
     * @dev Only executes once we've reached the minimum milestone target.
     */
    modifier thenMilestoneReached() {
        StateStorage memory state = _getStateStorage();
        require(
            state._totalRaised >= state._targets[0],
            "KVC: min milestone not reached"
        );
        _;
    }

    /**
     * @dev Only executes if we haven't yet reached the minimum milestone target.
     */
    modifier thenMilestoneNotReached() {
        StateStorage memory state = _getStateStorage();
        require(
            state._totalRaised < state._targets[0],
            "KVC: min milestone reached"
        );
        _;
    }

    // ---------------------------------------------------------------------
    // REFERRAL REWARD CLAIM
    // ---------------------------------------------------------------------

    /**
     * @notice Allows any user to claim accumulated referral rewards once the minimum milestone is reached.
     */
    function claimRefRewards() external thenMilestoneReached {
        _claimRefRewardsTo(_msgSender());
    }

    /**
     * @notice Admin/owner can process claims for multiple addresses in a single transaction.
     * @param users An array of addresses whose referral rewards should be claimed.
     */
    function claimRefRewardsBatch(
        address[] calldata users
    ) external thenMilestoneReached onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _claimRefRewardsTo(users[i]);
        }
    }

    /**
     * @dev Internal routine to finalize referral rewards payout to a specific address.
     */
    function _claimRefRewardsTo(address to) private {
        StateStorage storage state = _getStateStorage();
        UsersStorage storage uStore = _getUsersStorage();

        uint256 amount = uStore._user[to]._refRewards;
        if (amount > 0) {
            uStore._user[to]._refRewards = 0;
            state._totalRefRewardsClaimed += amount;
            _sendUsdt(to, amount);
            emit RefRewardsClaimed(to, amount);
        }
    }

    // ---------------------------------------------------------------------
    // TEAM WALLET & WITHDRAWAL
    // ---------------------------------------------------------------------

    /**
     * @notice Updates the team wallet address. Cannot be set to zero address.
     * @param teamWallet_ The new address for the team wallet.
     */
    function setTeamWallet(address teamWallet_) external onlyOwner {
        require(teamWallet_ != address(0), "KVC: zero team wallet");

        StateStorage storage state = _getStateStorage();
        emit TeamWalletChanged(state._teamWallet, teamWallet_);
        state._teamWallet = teamWallet_;
    }

    /**
     * @notice Withdraws any unclaimed portion of the funds to the team wallet, once the minimum milestone is met.
     *         Calculation accounts for the part reserved for the main car prize.
     */
    function withdraw() external thenMilestoneReached onlyOwner {
        StateStorage storage state = _getStateStorage();

        address teamWallet = state._teamWallet;

        // The total referral rewards (claimed + unclaimed)
        uint256 refRewards = state._totalRefRewardsClaimed +
            state._totalRefRewards;

        // The "carPrice" depends on which milestone the totalRaised has passed.
        uint256 carPrice = _getCarPrice();
        uint256 extra = 0;
        if (state._saleStopped) {
            // If sale is stopped, leftover beyond carPrice can be withdrawn
            extra = state._totalRaised - carPrice;
        }

        // Team gets 20% of the carPrice plus any leftover, minus the portion already claimed by ref + team
        uint256 sendAmount = ((carPrice * 2_000) / 10_000) +
            extra -
            refRewards -
            state._totalTeamRewardsClaimed;

        state._totalTeamRewards = 0;
        state._totalTeamRewardsClaimed += sendAmount;
        _sendUsdt(teamWallet, sendAmount);
        emit TeamRewardsClaimed(teamWallet, sendAmount);
    }

    /**
     * @dev Returns how much the "car" or main prize is set to cost, based on the highest milestone that was reached.
     */
    function _getCarPrice() private pure returns (uint256 carPrice) {
        StateStorage memory state = _getStateStorage();

        if (state._totalRaised >= state._targets[2]) {
            carPrice = state._targets[2];
        } else if (state._totalRaised >= state._targets[1]) {
            carPrice = state._targets[1];
        } else if (state._totalRaised >= state._targets[0]) {
            carPrice = state._targets[0];
        }
    }

    /**
     * @notice Allows admins to gift additional raffle tickets to selected addresses.
     * @param users Addresses receiving the tickets.
     * @param tickets Number of tickets per address.
     */
    function giftTickets(
        address[] calldata users,
        uint256[] calldata tickets
    ) external onlyAdminOrOwner {
        require(users.length == tickets.length, "KVC: length mismatch");
        for (uint256 i = 0; i < users.length; ++i) {
            _mintTickets(users[i], tickets[i]);
        }
    }

    // ========== Buyback section ==========

    /**
     * @dev Ensures the buyback phase is started.
     */
    modifier thenBuybackStarted() {
        StateStorage memory state = _getStateStorage();
        require(state._buybackStarted, "Buyback must be started");
        _;
    }

    /**
     * @dev Ensures the buyback phase has not yet started.
     */
    modifier thenBuybackNotStarted() {
        StateStorage memory state = _getStateStorage();
        require(!state._buybackStarted, "Buyback started");
        _;
    }

    /**
     * @notice Enables the buyback phase, allowing users to sell back their purchased cards.
     *         Irreversible once started.
     */
    function startBuyback()
        external
        thenSaleStopped
        thenDrawNotStarted
        thenBuybackNotStarted
        thenMilestoneNotReached
        onlyOwner
    {
        StateStorage storage state = _getStateStorage();
        state._buybackStarted = true;
        emit BuybackStarted();
    }

    /**
     * @notice Sells the caller's entire card collection back to the contract for a refund.
     */
    function buyback() external nonReentrant thenBuybackStarted {
        _buyback(_msgSender());
    }

    /**
     * @notice Allows an admin or owner to batch buyback cards from multiple users in one transaction.
     */
    function buybackBatch(
        address[] calldata users
    ) external nonReentrant thenBuybackStarted onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _buyback(users[i]);
        }
    }

    /**
     * @dev Internal routine for selling cards back to the contract.
     *      Iterates through each token ID, burning the user's holdings and sending them the appropriate USDT refund.
     */
    function _buyback(address to) private {
        StateStorage memory state = _getStateStorage();

        uint256 total = 0;
        // Tiers 0-3 correspond to token IDs [1..12]
        for (uint256 tokenId = 1; tokenId <= 12; ++tokenId) {
            uint256 balance = balanceOf(to, tokenId);
            if (balance > 0) {
                _burn(to, tokenId, balance);
                total += state._prices[_getTierByTokenId(tokenId)] * balance;
            }
        }

        if (total > 0) {
            _sendUsdt(to, total);
            emit Buyback(to, total);
        }
    }

    /**
     * @dev Calculates the tier based on the token ID.
     *      Each tier has 3 unique token IDs, e.g., Tier 0 -> IDs 1,2,3; Tier 1 -> IDs 4,5,6, etc.
     */
    function _getTierByTokenId(uint256 tokenId) private pure returns (uint256) {
        return (tokenId - 1) / 3;
    }

    // ========== Draw section ==========

    /**
     * @dev Ensures the lucky draw has been started.
     */
    modifier thenDrawStarted() {
        StateStorage memory state = _getStateStorage();
        require(state._drawStarted, "KVC: draw must be started");
        _;
    }

    /**
     * @dev Ensures the lucky draw is not yet started.
     */
    modifier thenDrawNotStarted() {
        StateStorage memory state = _getStateStorage();
        require(!state._drawStarted, "KVC: draw started");
        _;
    }

    /**
     * @notice Starts the draw phase, once the sale is stopped, buyback is not used,
     *         and the minimum milestone is met.
     */
    function startDraw()
        external
        thenSaleStopped
        thenBuybackNotStarted
        thenDrawNotStarted
        thenMilestoneReached
        onlyOwner
    {
        StateStorage storage state = _getStateStorage();
        state._drawStarted = true;
        emit DrawStarted();
    }

    /**
     * @dev Ensures that winners have already been awarded (for post-draw actions).
     */
    modifier thenWinnersAwarded() {
        StateStorage memory state = _getStateStorage();
        require(state._winnersAwarded, "KVC: winners not awarded");
        _;
    }

    /**
     * @dev Ensures that winners have NOT yet been awarded (for winner selection).
     */
    modifier thenWinnersNotAwarded() {
        StateStorage memory state = _getStateStorage();
        require(!state._winnersAwarded, "KVC: winners awarded");
        _;
    }

    /**
     * @notice Requests random words from Chainlink VRF to fairly select winners.
     *         This can only be called once, by the owner, after the draw phase starts.
     * @param keyHash Chainlink VRF key hash.
     * @param subscriptionId Chainlink VRF subscription ID.
     * @param requestConfirmations Number of confirmations the VRF node should wait before responding.
     * @param callbackGasLimit Gas limit for the fulfillRandomWords callback.
     */
    function selectWinners(
        bytes32 keyHash,
        uint64 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit
    ) external thenDrawStarted thenWinnersNotAwarded onlyOwner {
        VRFCoordinatorV2Interface(getVrfCoordinator()).requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1
        );
    }

    /**
     * @notice Allows the winning user (holding the winner token ID) to burn it in exchange for the prize amount in USDT.
     */
    function burnPrize() external nonReentrant thenWinnersAwarded {
        address sender = _msgSender();
        uint256 tokenId = _getWinnerTokenId();
        uint256 balance = balanceOf(sender, tokenId);
        require(balance > 0, "Not a winner");

        uint256 sendAmount = ((_getCarPrice() * 8_000) / 10_000);
        _burn(sender, tokenId, balance);
        _sendUsdt(sender, sendAmount);

        emit PrizeCashed(sender, tokenId, sendAmount);
    }

    /**
     * @notice Allows the owner to withdraw the portion of the "car" prize if it remains unclaimed, after winners are chosen.
     */
    function withdrawCarPrice() external thenWinnersAwarded onlyOwner {
        StateStorage memory state = _getStateStorage();

        address teamWallet = state._teamWallet;

        uint256 sendAmount = ((_getCarPrice() * 8_000) / 10_000);
        _sendUsdt(teamWallet, sendAmount);

        emit PrizeWithdrawn(teamWallet, sendAmount);
    }

    /**
     * @dev Chainlink VRF callback that receives a random word and mints winning tokens to randomly selected addresses.
     *      The first three winners receive ID #13 tokens (certificates), and the final winner receives the "car" token.
     */
    function _fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override thenDrawStarted thenWinnersNotAwarded {
        StateStorage storage state = _getStateStorage();

        address;
        uint256 winnersCounter = 0;
        uint256 iteration = 0;
        uint256 randomWord = randomWords[0];

        // Pick 4 winners in total:
        // - The first 3 get tokenId 13 (certificate)
        // - The last winner gets tokenId 14, 15, or 16, depending on totalRaised
        while (winnersCounter < 4) {
            uint256 winnerTokenId = winnersCounter < 3
                ? 13
                : _getWinnerTokenId();

            uint256 divider = winnersCounter < 3
                ? state._ticketsForCertificate
                : _ticketsTotal();

            uint256 ticketId = uint256(
                keccak256(abi.encodePacked(randomWord, iteration))
            ) % divider;

            address nextWinner = ticketsOwnerOf(ticketId);

            // Ensure no duplicates in the winners array
            if (!_contains(winners, nextWinner)) {
                winners[winnersCounter] = nextWinner;
                _mint(nextWinner, winnerTokenId, 1, "");
                emit Winner(nextWinner, winnerTokenId);
                winnersCounter++;
            }
            iteration++;
        }
        state._winnersAwarded = true;
    }

    /**
     * @dev Helper function to check if an address is already in the array of winners (avoid duplicates).
     */
    function _contains(
        address[] memory list,
        address target
    ) private pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == target) return true;
        }
        return false;
    }

    /**
     * @notice Opens peer‑to‑peer transfers on the secondary market (unpauses the contract),
     *         only after the draw is started and buyback is not used.
     */
    function startTrade()
        external
        thenSaleStopped
        thenBuybackNotStarted
        thenDrawStarted
        onlyOwner
    {
        _unpause();
        emit TradeStarted();
    }

    /**
     * @dev Returns the metadata URI for a given token ID, combining base URI with any override from Metadata lib.
     */
    function uri(
        uint256 tokenId
    )
        public
        view
        override(ERC1155Upgradeable, Metadata)
        returns (string memory)
    {
        return super.uri(tokenId);
    }

    /**
     * @dev Indicates which interfaces this contract supports (ERC165 standard).
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Upgradeable, Metadata) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Internal update function combining logic from ERC1155 and ERC1155Supply for supply tracking.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._update(from, to, ids, values);
    }

    /**
     * @dev Overridden safeTransferFrom that enforces a pause check (whenNotPaused modifier).
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public override whenNotPaused {
        super.safeTransferFrom(from, to, id, value, data);
    }

    /**
     * @dev Overridden safeBatchTransferFrom that also checks pause state.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public override whenNotPaused {
        super.safeBatchTransferFrom(from, to, ids, values, data);
    }
}
