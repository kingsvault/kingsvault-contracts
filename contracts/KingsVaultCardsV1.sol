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

/// @custom:security-contact hi@kingsvault.io
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

    struct StateStorage {
        bool _saleStopped; // if true primary sale is closed
        bool _buybackStarted; // if true holders can sell cards back
        bool _drawStarted; // if true lucky draw is active
        bool _winnersAwarded;
        address _teamWallet; // address that receives funds
        address _usdt; // USDT (18 decimals) payment token
        uint256 _buyers; // Number of unique buyers
        uint256 _ticketsForCertificate;
        uint256 _totalRaised; // total USDT collected from sales
        uint256 _totalTeamRewards;
        uint256 _totalTeamRewardsClaimed;
        uint256 _totalRefRewards; // total referral rewards accumulated
        uint256 _totalRefRewardsClaimed;
        uint256 _refPercentage; // referral percentage in basis points (1/10_000)
        uint256[] _prices; // price per tier in USDT (18 decimals)
        uint256[] _bonusTickets; // tickets granted per tier purchase
        uint256[] _targets; // funding targets in USDT (18 decimals)
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.state")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StateStorageLocation =
        0xbc62856e0c02dd21442d34f1898c6a8d302a7437a9cb81bf178895b7cbe27200;

    function _getStateStorage() private pure returns (StateStorage storage $) {
        assembly {
            $.slot := StateStorageLocation
        }
    }

    struct UserData {
        uint256 _spent;
        address _referrer;
        uint256 _refRewards;
    }

    struct UsersStorage {
        mapping(address => UserData) _user;
        mapping(address => bool) _admin;
        mapping(address => bool) _referrer;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.users")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UsersStorageLocation =
        0xbb2ab92c0b02289376da8cc9149aca642b578a5fcf5bd499c2b16904c1464200;

    function _getUsersStorage() private pure returns (UsersStorage storage $) {
        assembly {
            $.slot := UsersStorageLocation
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    //                                EVENTS
    // ──────────────────────────────────────────────────────────────────────

    event TeamWalletChanged(address indexed prev, address indexed next);
    event AdminChanged(address indexed admin, bool indexed status);
    event ReferrerChanged(address indexed referrer, bool indexed status);

    event SaleStopped();
    event BuybackStarted();
    event DrawStarted();
    event TradeStarted();

    event Purchase(
        address indexed user,
        uint256 indexed tier,
        uint256 quantity,
        uint256 tickets
    );
    event RefRewardsAccrued(
        address indexed referrer,
        address indexed user,
        uint256 amount
    );
    event RefRewardsClaimed(address indexed referrer, uint256 amount);
    event TeamRewardsAccrued(
        address indexed team,
        address indexed user,
        uint256 amount
    );
    event TeamRewardsClaimed(address indexed team, uint256 amount);

    event Buyback(address indexed user, uint256 amount);
    event Winner(address indexed winner, uint256 indexed tokenId);

    // ──────────────────────────────────────────────────────────────────────
    //                              INITIALIZER
    // ──────────────────────────────────────────────────────────────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Contract initializer (replaces constructor for upgradeable pattern).
     * @param initialOwner_    First owner / admin.
     * @param usdt_            ERC‑20 USDT token used for payments.
     * @param teamWallet_      Address that will receive funds.
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

        state._refPercentage = 500; // 500/10_000 = 5%

        // Price per card tier (18 decimals USDT).
        state._prices.push(5_000000000000000000);
        state._prices.push(25_000000000000000000);
        state._prices.push(88_000000000000000000);
        state._prices.push(250_000000000000000000);

        // Bonus tickets per card purchased for each tier.
        state._bonusTickets.push(5);
        state._bonusTickets.push(35);
        state._bonusTickets.push(150);
        state._bonusTickets.push(500);

        // Funding milestones (18 decimals USDT).
        state._targets.push(75_000_000000000000000000);
        state._targets.push(265_000_000000000000000000);
        state._targets.push(350_000_000000000000000000);

        // --------------------------- Admin set‑up ------------------------
        UsersStorage storage uStore = _getUsersStorage();
        uStore._admin[initialOwner_] = true;
        emit AdminChanged(initialOwner_, true);

        // --------------------------- Initial state -----------------------
        _pause(); // primary sale is closed until owner calls startTrade().
    }

    /**
     * @dev Returns the version of the token contract.
     * This can be useful for identifying the deployed version of the contract, especially after upgrades.
     * @return The version string of the contract.
     */
    function version() external view virtual returns (string memory) {
        return "1";
    }

    function getState() external view returns (StateStorage memory) {
        StateStorage memory state = _getStateStorage();
        return state;
    }

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

    modifier onlyAdminOrOwner() {
        address sender = _msgSender();
        UsersStorage storage uStore = _getUsersStorage();
        require(
            uStore._admin[sender] || sender == owner(),
            "KVC: only admin or owner"
        );
        _;
    }

    /// @notice Adds or removes an auxiliary admin.
    function setAdmin(address wallet, bool status) external onlyOwner {
        UsersStorage storage uStore = _getUsersStorage();
        uStore._admin[wallet] = status;
        emit AdminChanged(wallet, status);
    }

    function isAdmin(address wallet) external view returns (bool) {
        UsersStorage storage uStore = _getUsersStorage();
        return uStore._admin[wallet];
    }

    function setReferrer(address wallet, bool status) external onlyOwner {
        UsersStorage storage uStore = _getUsersStorage();
        uStore._referrer[wallet] = status;
        emit ReferrerChanged(wallet, status);
    }

    function isReferrer(address wallet) external view returns (bool) {
        UsersStorage storage uStore = _getUsersStorage();
        return uStore._referrer[wallet];
    }

    // ========== Sale section ==========

    modifier thenSaleStopped() {
        StateStorage memory state = _getStateStorage();
        require(state._saleStopped, "KVC: sale must be stopped");
        _;
    }

    modifier thenSaleNotStopped() {
        StateStorage memory state = _getStateStorage();
        require(!state._saleStopped, "KVC: sale stopped");
        _;
    }

    /// @notice Permanently closes primary sale.
    function stopSale() external thenSaleNotStopped onlyOwner {
        StateStorage storage state = _getStateStorage();
        state._saleStopped = true;
        emit SaleStopped();
    }

    /**
     * @notice Purchases `qty` cards of a certain `tier` for `msg.sender`.
     * @param tier  Card tier (0‑3).
     * @param qty   Amount of cards to purchase.
     * @param ref   Optional referrer address.
     */
    function buy(uint256 tier, uint256 qty, address ref) external {
        _buyTo(_msgSender(), tier, qty, ref);
    }

    /**
     * @notice Purchases cards for a different address.
     * @dev No access restriction because payment is made by caller.
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
     * @dev Internal purchase function that handles payment, referral logic, ticket minting and card minting.
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

        uint256 cost = state._prices[tier] * qty;
        require(
            IERC20(state._usdt).transferFrom(_msgSender(), address(this), cost),
            "KVC: payment failed"
        );

        if (uStore._user[to]._spent == 0) {
            state._buyers++;
        }

        state._totalRaised += cost;
        uint256 refRewards = _doRefRewards(to, ref, cost);
        _doTeamRewards(to, cost, refRewards);
        uStore._user[to]._spent += cost;

        for (uint256 i = 0; i < qty; i++) {
            _mint(to, _getRandomTokenId(tier), 1, "");
        }

        uint256 newTickets = state._bonusTickets[tier] * qty;
        _mintTickets(to, newTickets);

        if (state._buyers <= 1000) {
            state._ticketsForCertificate = _ticketsTotal();
        }

        emit Purchase(to, tier, qty, newTickets);
    }

    function _doRefRewards(
        address buyer,
        address ref,
        uint256 cost
    ) private returns (uint256 refRewards) {
        StateStorage storage state = _getStateStorage();
        UsersStorage storage uStore = _getUsersStorage();

        if (uStore._user[buyer]._referrer != address(0)) {
            ref = uStore._user[buyer]._referrer;
        }

        if (!uStore._referrer[ref] || ref == buyer) {
            return 0;
        }

        if (
            uStore._user[buyer]._spent == 0 &&
            uStore._user[buyer]._referrer == address(0)
        ) {
            uStore._user[buyer]._referrer = ref;
        }

        refRewards = (cost * 500) / 10_000; // 5%
        state._totalRefRewards += refRewards;

        emit RefRewardsAccrued(ref, buyer, refRewards);
        if (state._totalRaised < state._targets[0]) {
            uStore._user[ref]._refRewards += refRewards;
            return refRewards;
        }

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

    function _doTeamRewards(
        address buyer,
        uint256 cost,
        uint256 refRewards
    ) private returns (uint256 teamRewards) {
        StateStorage storage state = _getStateStorage();
        UsersStorage storage uStore = _getUsersStorage();

        address teamWallet = state._teamWallet;

        if (state._totalRaised < state._targets[2]) {
            teamRewards = ((cost * 2_000) / 10_000) - refRewards; // 20% [- 5%]
        } else if ((state._totalRaised - cost) < state._targets[2]) {
            uint256 extra = state._totalRaised - state._targets[2];
            uint256 targetDelta = cost - extra;
            teamRewards = ((targetDelta * 2_000) / 10_000) + extra - refRewards;
        } else {
            teamRewards = cost - refRewards; // 100% [- 5%]
        }

        emit TeamRewardsAccrued(teamWallet, buyer, teamRewards);
        if (state._totalRaised < state._targets[0]) {
            state._totalTeamRewards += teamRewards;
            return teamRewards;
        }

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

    function _sendUsdt(address to, uint256 amount) private {
        StateStorage memory state = _getStateStorage();
        require(
            IERC20(state._usdt).transfer(to, amount),
            "KVC: USDT transfer failed"
        );
    }

    /**
     * @dev Pseudo‑random card ID generator.
     * For the presale we rely on block attributes
     * which are sufficiently random for non‑critical use‑cases.
     */
    function _getRandomTokenId(uint256 tier) private view returns (uint256) {
        uint256 baseId = tier * 3 + 1; // tiers are grouped by 3 IDs
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    _msgSender(),
                    totalSupply()
                )
            )
        ) % 3; // range 0‑2
        return baseId + random;
    }

    function _getWinnerTokenId() private view returns (unit256) {
        StateStorage memory state = _getStateStorage();
        if (state._totalRaised >= state._targets[2]) return 16;
        else if (state._totalRaised >= state._targets[1]) return 15;
        else return 14;
    }

    modifier thenMilestoneReached() {
        StateStorage memory state = _getStateStorage();
        require(
            state._totalRaised >= state._targets[0],
            "KVC: min milestone not reached"
        );
        _;
    }

    modifier thenMilestoneNotReached() {
        StateStorage memory state = _getStateStorage();
        require(
            state._totalRaised < state._targets[0],
            "KVC: min milestone reached"
        );
        _;
    }

    /// @notice Claims accumulated referral rewards.
    function claimRefRewards() external thenMilestoneReached {
        _claimRefRewardsTo(_msgSender());
    }

    function claimRefRewardsBatch(
        address[] calldata users
    ) external thenMilestoneReached onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _claimRefRewardsTo(users[i]);
        }
    }

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

    /// @notice Updates team wallet address.
    function setTeamWallet(address teamWallet_) external onlyOwner {
        require(teamWallet_ != address(0), "KVC: zero team wallet");

        StateStorage storage state = _getStateStorage();
        emit TeamWalletChanged(state._teamWallet, teamWallet_);
        state._teamWallet = teamWallet_;
    }

    /// @notice Withdraws collected USDT to team wallet.
    function withdraw() external thenMilestoneReached onlyOwner {
        StateStorage storage state = _getStateStorage();

        address teamWallet = state._teamWallet;

        uint256 refRewards = state._totalRefRewardsClaimed +
            state._totalRefRewards;

        uint256 carPrice = _getCarPrice();
        uint256 extra = 0;
        if (state._saleStopped) {
            extra = state._totalRaised - carPrice;
        }

        uint256 sendAmount = ((carPrice * 2_000) / 10_000) +
            extra -
            refRewards -
            state._totalTeamRewardsClaimed;

        state._totalTeamRewards = 0;
        state._totalTeamRewardsClaimed += sendAmount;
        _sendUsdt(teamWallet, sendAmount);
        emit TeamRewardsClaimed(teamWallet, sendAmount);
    }

    function _getCarPrice() private view returns (uint256 carPrice) {
        StateStorage memory state = _getStateStorage();

        if (state._totalRaised >= state._targets[2]) {
            carPrice = state._targets[2];
        } else if (state._totalRaised >= state._targets[1]) {
            carPrice = state._targets[1];
        } else if (state._totalRaised >= state._targets[0]) {
            carPrice = state._targets[0];
        }
    }

    /// @notice Gifts tickets to a list of users.
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

    modifier thenBuybackStarted() {
        StateStorage memory state = _getStateStorage();
        require(state._buybackStarted, "Buyback must be started");
        _;
    }

    modifier thenBuybackNotStarted() {
        StateStorage memory state = _getStateStorage();
        require(!state._buybackStarted, "Buyback started");
        _;
    }

    /// @notice Enables card buy‑back (irreversible).
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

    /// @notice Sells caller's entire card collection back to the contract.
    function buyback() external nonReentrant thenBuybackStarted {
        _buyback(_msgSender());
    }

    /// @notice Batch buy‑back helper for admins.
    function buybackBatch(
        address[] calldata users
    ) external nonReentrant thenBuybackStarted onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _buyback(users[i]);
        }
    }

    /// @dev Internal buy‑back routine.
    function _buyback(address to) private {
        StateStorage memory state = _getStateStorage();

        uint256 total = 0;
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

    /// @dev Returns tier by card ID (each tier spans 3 IDs).
    function _getTierByTokenId(uint256 tokenId) private pure returns (uint256) {
        return (tokenId - 1) / 3;
    }

    // ========== Draw section ==========

    modifier thenDrawStarted() {
        StateStorage memory state = _getStateStorage();
        require(state._drawStarted, "KVC: draw must be started");
        _;
    }

    modifier thenDrawNotStarted() {
        StateStorage memory state = _getStateStorage();
        require(!state._drawStarted, "KVC: draw started");
        _;
    }

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

    modifier thenWinnersAwarded() {
        StateStorage memory state = _getStateStorage();
        require(state._winnersAwarded, "KVC: winners not awarded");
        _;
    }

    modifier thenWinnersNotAwarded() {
        StateStorage memory state = _getStateStorage();
        require(!state._winnersAwarded, "KVC: winners awarded");
        _;
    }

    function selectWinners(
        bytes32 keyHash,
        uint64 subscriptionId,
        uint256 requestConfirmations,
        uint256 callbackGasLimit
    ) external thenDrawStarted thenWinnersNotAwarded onlyOwner {
        StateStorage memory state = _getStateStorage();

        VRFCoordinatorV2Interface(getVrfCoordinator()).requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1
        );
    }

    function burnPrize() external nonReentrant thenWinnersAwarded {
        address sender = _msgSender();
        uint256 tokenId = _getWinnerTokenId();
        uint256 balance = balanceOf(sender, tokenId);
        require(balance > 0, "Not a winner");

        uint256 sendAmount = ((_getCarPrice() * 8_000) / 10_000);
        _burn(sender, tokenId, balance);
        _sendUsdt(sender, refund);

        emit PrizeBurned(sender, tokenId, balance);
    }

    function withdrawCarPrice() external thenWinnersAwarded onlyOwner {
        StateStorage memory state = _getStateStorage();
        uint256 sendAmount = ((_getCarPrice() * 8_000) / 10_000);
        _sendUsdt(state._teamWallet, sendAmount);

        emit PrizeBurned(sender, tokenId, balance);
    }

    function _fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override thenDrawStarted thenWinnersNotAwarded {
        StateStorage storage state = _getStateStorage();

        address[] memory winners = new address[](4);
        uint256 winnersCounter = 0;
        uint256 iteration = 0;
        uint256 randomWord = randomWords[0];
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
            if (!_contains(winners, nextWinner)) {
                winners[winnersCounter] = nextWinner;
                _mint(nextWinner, winnerTokenId, 1, "");
                emit Winner(winner, winnerTokenId);
                winnersCounter++;
            }
            iteration++;
        }
        state._winnersAwarded = true;
    }

    function _contains(
        address[] memory list,
        address target
    ) private pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == target) return true;
        }
        return false;
    }

    /// @notice Opens peer‑to‑peer transfers (secondary market).
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

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Upgradeable, Metadata) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._update(from, to, ids, values);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public override whenNotPaused {
        super.safeTransferFrom(from, to, id, value, data);
    }

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
