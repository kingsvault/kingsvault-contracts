// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155Upgradeable} from "./lib/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from "./lib/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "./lib/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransientUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import {VRFConsumerBaseV2, VRFCoordinatorV2Interface} from "./lib/VRFConsumerBaseV2.sol";
import {Metadata} from "./lib/Metadata.sol";
import {Tickets} from "./lib/Tickets.sol";
import {TicketsQueryable} from "./lib/TicketsQueryable.sol";
import {IKingsVaultCards} from "./interfaces/IKingsVaultCards.sol";

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
    Metadata,
    VRFConsumerBaseV2,
    ReentrancyGuardTransientUpgradeable,
    Tickets,
    TicketsQueryable,
    IKingsVaultCards
{
    // ──────────────────────────────────────────────────────────────────────
    //                               STORAGE
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev Returns a pointer to the StateStorage struct in storage.
     */
    function _getStateStorage() private pure returns (StateStorage storage $) {
        // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.state")) - 1)) & ~bytes32(uint256(0xff))
        assembly {
            $.slot := 0xbc62856e0c02dd21442d34f1898c6a8d302a7437a9cb81bf178895b7cbe27200
        }
    }

    /**
     * @dev Returns a pointer to the CounterStorage struct in storage.
     */
    function _getCounterStorage()
        private
        pure
        returns (CounterStorage storage $)
    {
        // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.counter")) - 1)) & ~bytes32(uint256(0xff))
        assembly {
            $.slot := 0x40fa8b772f9360dea45857f7caa42805cf5c48a83c52931d8ed033d331886f00
        }
    }

    /**
     * @dev Returns a pointer to the UsersStorage struct in storage.
     */
    function _getUsersStorage() private pure returns (UsersStorage storage $) {
        // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.users")) - 1)) & ~bytes32(uint256(0xff))
        assembly {
            $.slot := 0xbb2ab92c0b02289376da8cc9149aca642b578a5fcf5bd499c2b16904c1464200
        }
    }

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
     * @param vrfCoordinator_  Chainlink VRF coordinator address.
     */
    function initialize(
        address initialOwner_,
        address vrfCoordinator_
    ) public virtual initializer {
        // -------------------------- OZ initializers ----------------------
        __ERC1155_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __Ownable_init(initialOwner_);

        // --------------------------- Project libs ------------------------
        __Metadata_init(
            "https://kingsvault.github.io/metadata/",
            "Kings Vault Cards",
            "KVC"
        );
        __Tickets_init();
        __TicketsQueryable_init();
        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_);

        // --------------------------- Admin set‑up ------------------------
        _getUsersStorage()._admin[initialOwner_] = true;
        emit AdminChanged(initialOwner_, true);
    }

    function _usdt() private pure returns (IERC20) {
        return IERC20(address(0)); // TODO
    }

    function _teamWallet() private pure returns (address) {
        return address(0); // TODO
    }

    function _fenominator() private pure returns (uint256) {
        return 10_000;
    }

    function _calculateRefRewards(
        uint256 value
    ) private pure returns (uint256) {
        return (value * 500) / _fenominator();
    }

    function _calculateTeamRewardsRaw(
        uint256 value
    ) private pure returns (uint256) {
        return (value * 2_000) / _fenominator();
    }

    function _calculateCarPrice(uint256 value) private pure returns (uint256) {
        return (value * 8_000) / _fenominator();
    }

    /// @dev Bonus tickets granted per card purchase for each tier.
    function _bonusTickets(
        uint256 tier
    ) private pure returns (uint256 ticketsPerTier) {
        if (tier == 0) return 5;
        else if (tier == 1) return 35;
        else if (tier == 2) return 150;
        else if (tier == 3) return 500;
    }

    /// @dev Funding milestones (18 decimals) at which different contract logic may unlock or change.
    function _target(uint256 carId) private pure returns (uint256 target) {
        if (carId == 0) return 75_000_000000000000000000;
        else if (carId == 1) return 265_000_000000000000000000;
        else if (carId == 2) return 350_000_000000000000000000;
    }

    /// @dev Price per card tier (in USDT with 18 decimals)
    function _carPrice(uint256 tier) private pure returns (uint256 carPrice) {
        if (tier == 0) return 5_000000000000000000;
        else if (tier == 1) return 25_000000000000000000;
        else if (tier == 2) return 88_000000000000000000;
        else if (tier == 3) return 250_000000000000000000;
    }

    function _totalRaised() private view returns (uint256) {
        return _getCounterStorage()._totalRaised;
    }

    /**
     * @dev Returns how much the "car" or main prize is set to cost, based on the highest milestone that was reached.
     */
    function _getCarPrice() private view returns (uint256 carPrice) {
        uint256 totalRaised = _totalRaised();

        if (totalRaised >= _target(2)) {
            return _target(2);
        } else if (totalRaised >= _target(1)) {
            return _target(1);
        } else if (totalRaised >= _target(0)) {
            return _target(0);
        }
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
        return _getStateStorage();
    }

    /**
     * @notice Returns a copy of the contract's CounterStorage struct.
     */
    function getCounter() external pure returns (CounterStorage memory) {
        return _getCounterStorage();
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
        if (!_getUsersStorage()._admin[sender] && sender != owner()) {
            revert OnlyAdminOrOwner();
        }
        _;
    }

    /**
     * @notice Adds or removes an auxiliary admin. Admins have special privileges like batch buyback or batch claim.
     * @param wallet The address to grant or revoke admin rights.
     * @param status True to grant admin, false to revoke.
     */
    function setAdmin(address wallet, bool status) external onlyOwner {
        _getUsersStorage()._admin[wallet] = status;
        emit AdminChanged(wallet, status);
    }

    /**
     * @notice Checks if a given address is an admin.
     * @param wallet The address to query.
     * @return True if the address has admin rights, false otherwise.
     */
    function isAdmin(address wallet) external view returns (bool) {
        return _getUsersStorage()._admin[wallet];
    }

    /**
     * @notice Assigns or revokes referral status for a given address.
     * @param wallet The address to grant or revoke referral privileges.
     * @param status True to mark as a referrer, false to revoke.
     */
    function setReferrer(address wallet, bool status) external onlyOwner {
        _getUsersStorage()._referrer[wallet] = status;
        emit ReferrerChanged(wallet, status);
    }

    /**
     * @notice Checks if a given address is a registered referrer.
     * @param wallet The address to query.
     * @return True if the address is a referrer, false otherwise.
     */
    function isReferrer(address wallet) external view returns (bool) {
        return _getUsersStorage()._referrer[wallet];
    }

    // ========== Sale section ==========

    /**
     * @dev Ensures the primary sale has been stopped.
     */
    modifier thenSaleStopped() {
        if (!_getStateStorage()._saleStopped) {
            revert SaleMustBeStopped();
        }
        _;
    }

    /**
     * @dev Ensures the primary sale is still ongoing.
     */
    modifier thenSaleNotStopped() {
        if (_getStateStorage()._saleStopped) {
            revert SaleAlreadyStopped();
        }
        _;
    }

    /**
     * @notice Permanently closes primary sale for new cards.
     *         Once stopped, it cannot be restarted.
     */
    function stopSale() external thenSaleNotStopped onlyOwner {
        _getStateStorage()._saleStopped = true;
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
        if (tier >= 4) {
            revert InvalidTier();
        }
        if (qty == 0) {
            revert ZeroQuantity();
        }

        CounterStorage storage counter = _getCounterStorage();
        UsersStorage storage uStore = _getUsersStorage();

        // Calculate total cost and pull USDT from buyer
        uint256 cost = _carPrice(tier) * qty;
        bool success = _usdt().transferFrom(_msgSender(), address(this), cost);
        if (!success) {
            revert PaymentFailed();
        }

        // Increment buyer count if this is the user's first purchase
        if (uStore._user[to]._spent == 0) {
            counter._buyers++;
        }

        counter._totalRaised += cost;
        uint256 refRewards = _doRefRewards(to, ref, cost);
        _doTeamRewards(to, cost, refRewards);
        uStore._user[to]._spent += cost;

        // Mint the requested number of NFTs in the chosen tier
        for (uint256 i = 0; i < qty; i++) {
            _mint(to, _getRandomTokenId(tier), 1, "");
        }

        // Mint the appropriate number of bonus tickets
        uint256 newTickets = _bonusTickets(tier) * qty;
        _mintTickets(to, newTickets);

        // Track a special cutoff (1000 initial buyers) for an extra certificate draw
        if (counter._buyers <= 1000) {
            counter._ticketsForCertificate = _ticketsTotal();
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
        CounterStorage storage counter = _getCounterStorage();
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
        refRewards = _calculateRefRewards(cost);
        counter._totalRefRewards += refRewards;

        emit RefRewardsAccrued(ref, buyer, refRewards);

        // If we haven't reached the first milestone, store rewards in user’s account
        if (_totalRaised() < _target(0)) {
            uStore._user[ref]._refRewards += refRewards;
            return refRewards;
        }

        // Otherwise, pay out immediately
        uint256 sendAmount = refRewards;
        if (uStore._user[ref]._refRewards > 0) {
            sendAmount += uStore._user[ref]._refRewards;
            uStore._user[ref]._refRewards = 0;
        }

        counter._totalRefRewardsClaimed += sendAmount;
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
        CounterStorage storage counter = _getCounterStorage();

        address teamWallet = _teamWallet();
        uint256 totalRaised = _totalRaised();

        // If final target isn't reached, team gets 20% minus 5% referral => 15%.
        // If final target was reached mid-transaction, partial calculations are made.
        if (totalRaised < _target(2)) {
            teamRewards = _calculateTeamRewardsRaw(cost) - refRewards; // 20% minus referral
        } else if ((totalRaised - cost) < _target(2)) {
            // If the transaction itself crossed the last milestone boundary, do partial distribution
            uint256 extra = totalRaised - _target(2);
            uint256 targetDelta = cost - extra;
            teamRewards =
                _calculateTeamRewardsRaw(targetDelta) +
                extra -
                refRewards;
        } else {
            // Past final target, team effectively gets the full cost minus referral.
            teamRewards = cost - refRewards;
        }

        emit TeamRewardsAccrued(teamWallet, buyer, teamRewards);

        // If we haven't reached the first milestone, store team rewards on contract
        if (totalRaised < _target(0)) {
            counter._totalTeamRewards += teamRewards;
            return teamRewards;
        }

        // Otherwise, pay out immediately
        uint256 sendAmount = teamRewards;
        if (counter._totalTeamRewards > 0) {
            sendAmount += counter._totalTeamRewards;
            counter._totalTeamRewards = 0;
        }

        counter._totalTeamRewardsClaimed += sendAmount;
        _sendUsdt(teamWallet, sendAmount);
        emit TeamRewardsClaimed(teamWallet, sendAmount);

        return teamRewards;
    }

    /**
     * @dev Safely sends USDT from this contract to the specified address.
     *      Reverts if the transfer fails.
     */
    function _sendUsdt(address to, uint256 amount) private {
        bool success = _usdt().transfer(to, amount);
        if (!success) {
            revert USDTTransferFailed();
        }
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
    function _getWinnerTokenId() private view returns (uint256) {
        uint256 totalRaised = _totalRaised();
        if (totalRaised >= _target(2)) return 16;
        else if (totalRaised >= _target(1)) return 15;
        else return 14;
    }

    /**
     * @dev Only executes once we've reached the minimum milestone target.
     */
    modifier thenMilestoneReached() {
        if (_totalRaised() < _target(0)) {
            revert MilestoneNotReached();
        }
        _;
    }

    /**
     * @dev Only executes if we haven't yet reached the minimum milestone target.
     */
    modifier thenMilestoneNotReached() {
        if (_totalRaised() >= _target(0)) {
            revert MilestoneReached();
        }
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
        UsersStorage storage uStore = _getUsersStorage();

        uint256 amount = uStore._user[to]._refRewards;
        if (amount > 0) {
            uStore._user[to]._refRewards = 0;
            _getCounterStorage()._totalRefRewardsClaimed += amount;
            _sendUsdt(to, amount);
            emit RefRewardsClaimed(to, amount);
        }
    }

    // ---------------------------------------------------------------------
    // TEAM WALLET & WITHDRAWAL
    // ---------------------------------------------------------------------

    /**
     * @notice Withdraws any unclaimed portion of the funds to the team wallet, once the minimum milestone is met.
     *         Calculation accounts for the part reserved for the main car prize.
     */
    function withdraw() external thenMilestoneReached onlyOwner {
        CounterStorage storage counter = _getCounterStorage();

        address teamWallet = _teamWallet();

        // The total referral rewards (claimed + unclaimed)
        uint256 refRewards = counter._totalRefRewardsClaimed +
            counter._totalRefRewards;

        // The "carPrice" depends on which milestone the totalRaised has passed.
        uint256 carPrice = _getCarPrice();
        uint256 extra = 0;
        if (_getStateStorage()._saleStopped) {
            // If sale is stopped, leftover beyond carPrice can be withdrawn
            extra = _totalRaised() - carPrice;
        }

        // Team gets 20% of the carPrice plus any leftover, minus the portion already claimed by ref + team
        uint256 sendAmount = _calculateTeamRewardsRaw(carPrice) +
            extra -
            refRewards -
            counter._totalTeamRewardsClaimed;

        counter._totalTeamRewards = 0;
        counter._totalTeamRewardsClaimed += sendAmount;
        _sendUsdt(teamWallet, sendAmount);
        emit TeamRewardsClaimed(teamWallet, sendAmount);
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
        if (users.length != tickets.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < users.length; ++i) {
            _mintTickets(users[i], tickets[i]);
        }
    }

    // ========== Buyback section ==========

    /**
     * @dev Ensures the buyback phase is started.
     */
    modifier thenBuybackStarted() {
        if (!_getStateStorage()._buybackStarted) {
            revert BuybackMustBeStarted();
        }
        _;
    }

    /**
     * @dev Ensures the buyback phase has not yet started.
     */
    modifier thenBuybackNotStarted() {
        if (_getStateStorage()._buybackStarted) {
            revert BuybackAlreadyStarted();
        }
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
        _getStateStorage()._buybackStarted = true;
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
        uint256 total = 0;
        // Tiers 0-3 correspond to token IDs [1..12]
        for (uint256 tokenId = 1; tokenId <= 12; ++tokenId) {
            uint256 balance = balanceOf(to, tokenId);
            if (balance > 0) {
                _burn(to, tokenId, balance);
                total += _carPrice(_getTierByTokenId(tokenId)) * balance;
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
        if (!_getStateStorage()._drawStarted) {
            revert DrawMustBeStarted();
        }
        _;
    }

    /**
     * @dev Ensures the lucky draw is not yet started.
     */
    modifier thenDrawNotStarted() {
        if (_getStateStorage()._drawStarted) {
            revert DrawAlreadyStarted();
        }
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
        _getStateStorage()._drawStarted = true;
        emit DrawStarted();
    }

    /**
     * @dev Ensures that winners have already been awarded (for post-draw actions).
     */
    modifier thenWinnersAwarded() {
        if (!_getStateStorage()._winnersAwarded) {
            revert WinnersNotAwarded();
        }
        _;
    }

    /**
     * @dev Ensures that winners have NOT yet been awarded (for winner selection).
     */
    modifier thenWinnersNotAwarded() {
        if (_getStateStorage()._winnersAwarded) {
            revert WinnersAlreadyAwarded();
        }
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
        if (balance == 0) {
            revert NotAWinner();
        }

        uint256 sendAmount = _calculateCarPrice(_getCarPrice());
        _burn(sender, tokenId, balance);
        _sendUsdt(sender, sendAmount);

        emit PrizeCashed(sender, tokenId, sendAmount);
    }

    /**
     * @notice Allows the owner to withdraw the portion of the "car" prize if it remains unclaimed, after winners are chosen.
     */
    function withdrawCarPrice() external thenWinnersAwarded onlyOwner {
        address teamWallet = _teamWallet();

        uint256 sendAmount = _calculateCarPrice(_getCarPrice());
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
        address[] memory winners = new address[](4);
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
                ? _getCounterStorage()._ticketsForCertificate
                : _ticketsTotal();

            uint256 ticketId = uint256(
                keccak256(abi.encodePacked(randomWord, iteration))
            ) % divider;

            address nextWinner = ticketsOwnerOf(ticketId);

            // Ensure no duplicates in the winners array
            bool isDuplicate = false;
            for (uint256 i = 0; i < winners.length; i++) {
                if (winners[i] == nextWinner) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate) {
                winners[winnersCounter] = nextWinner;
                _mint(nextWinner, winnerTokenId, 1, "");
                emit Winner(nextWinner, winnerTokenId);
                winnersCounter++;
            }
            iteration++;
        }
        _getStateStorage()._winnersAwarded = true;
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
}
