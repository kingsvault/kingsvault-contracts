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
        address _teamWallet; // address that receives funds
        address _usdt; // USDT (6 decimals) payment token
        uint256 _buyers; // Number of unique buyers
        uint256 _ticketsForCertificate;
        uint256 _totalRaised; // total USDT collected from sales
        uint256 _totalTeamRewards;
        uint256 _totalRefRewards; // total referral rewards accumulated
        uint256 _totalRefRewardsClaimed;
        uint256 _refPercentage; // referral percentage in basis points (1/10_000)
        uint256[] _prices; // price per tier in USDT (6 decimals)
        uint256[] _bonusTickets; // tickets granted per tier purchase
        uint256[] _targets; // funding targets
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
    event AdminChanged(address indexed wallet, bool indexed status);
    event ReferrerChanged(address indexed wallet, bool indexed status);

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
        address indexed referral,
        uint256 amount
    );
    event RefRewardsClaimed(address indexed referrer, uint256 amount);

    event Buyback(address indexed user, uint256 amount);

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

        state._refPercentage = 500; // 500/10_000 = 5%
        state._usdt = usdt_;
        emit TeamWalletChanged(state._teamWallet, teamWallet_);
        state._teamWallet = teamWallet_;

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

    //+
    function setReferrer(address wallet, bool status) external onlyOwner {
        UsersStorage storage uStore = _getUsersStorage();
        uStore._referrer[wallet] = status;
        emit ReferrerChanged(wallet, status);
    }

    //+
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

    // ========== Sale section ==========
    //+
    modifier thenSaleStopped() {
        StateStorage memory state = _getStateStorage();
        require(state._saleStopped, "KVC: sale must be stopped");
        _;
    }

    //+
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

    //++
    /**
     * @notice Purchases `qty` cards of a certain `tier` for `msg.sender`.
     * @param tier  Card tier (0‑3).
     * @param qty   Amount of cards to purchase.
     * @param ref   Optional referrer address.
     */
    function buy(uint256 tier, uint256 qty, address ref) external {
        _buyTo(_msgSender(), tier, qty, ref);
    }

    //++
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

    //++
    /**
     * @dev Internal purchase function that handles payment, referral logic,
     * ticket minting and card minting.
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

        state._totalRaised += cost;
        if (uStore._user[to]._spent == 0) {
            state._buyers++;
        }

        uint256 refRewards = _doRefRewards(to, ref, cost);
        uint256 refRewards = _doTeamRewards(to, ref, cost);
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

    //++
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

        refRewards = (cost * 500) / 10_000;
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

        teamRewards = ((cost * 2_000) / 10_000) - refRewards;
        //state._totalRefRewards += refRewards;

        //emit RefRewardsAccrued(ref, buyer, refRewards);
        //if (state._totalRaised < state._targets[0]) {
        //    uStore._user[ref]._refRewards += refRewards;
        //    return refRewards;
        //}

        uint256 sendAmount = teamRewards;

        //state._totalRefRewardsClaimed += sendAmount;
        //_sendUsdt(ref, sendAmount);
        //emit RefRewardsClaimed(ref, sendAmount);

        //_totalTeamRewards

        return teamRewards;
    }

    //++
    function _sendUsdt(address to, uint256 amount) private {
        StateStorage memory state = _getStateStorage();
        require(
            IERC20(state._usdt).transfer(to, amount),
            "KVC: USDT transfer failed"
        );
    }

    //++
    /**
     * @dev Pseudo‑random card ID generator.
     * For the presale we rely on block attributes
     * which are sufficiently random for non‑critical use‑cases.
     */
    function _getRandomTokenId(uint256 tier) private view returns (uint256) {
        uint256 baseId = tier * 10 + 1; // tiers are grouped by 10 IDs
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    _msgSender(),
                    totalSupply()
                )
            )
        ) % 10; // range 0‑9
        return baseId + random;
    }

    //++
    modifier thenMilestoneReached() {
        StateStorage memory state = _getStateStorage();
        require(
            state._totalRaised >= state._targets[0],
            "KVC: min milestone not reached"
        );
        _;
    }

    //++
    modifier thenMilestoneNotReached() {
        StateStorage memory state = _getStateStorage();
        require(
            state._totalRaised < state._targets[0],
            "KVC: min milestone reached"
        );
        _;
    }

    //++
    /// @notice Claims accumulated referral rewards.
    function claimRefRewards() external thenMilestoneReached {
        _claimRefRewardsTo(_msgSender());
    }

    //++
    function claimRefRewardsBatch(
        address[] calldata users
    ) external thenMilestoneReached onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _claimRefRewardsTo(users[i]);
        }
    }

    //++
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

    /// Possible available team rewards
    function _availableTeamRewards()
        private
        view
        returns (uint256 teamRewards)
    {
        StateStorage storage state = _getStateStorage();
        teamRewards =
            ((state._totalRaised * 2_000) / 10_000) -
            state._totalRefRewards;

        // ?
        if (state._totalRaised >= state._targets[2]) {
            // total raised - car price - ref rewards - team rewards
            uint256 extra = state._totalRaised -
                ((state._targets[2] * 8_000) / 10_000) -
                state._totalRefRewards -
                teamRewards;
        }
    }

    /// @notice Withdraws collected USDT to team wallet.
    function withdraw() external thenMilestoneReached onlyOwner {
        StateStorage storage state = _getStateStorage();
        require(state._teamWallet != address(0), "KVC: zero team wallet");

        // ?
        uint256 amount = (state._totalRaised * (2_000 - state._refPercentage)) /
            10_000 -
            (state._totalRefRewards - state._totalRefRewardsClaimed);
        //? всего сборов  - минимальный порог, 80%,  ?- реф реварды
        // _totalWithdrawn
        //_totalTeamRewards

        _sendUsdt(state._teamWallet, amount);
    }

    // ?
    function withdrawCarPrice() external onlyOwner {
        //
    }

    /// @notice Gifts tickets to a list of users.
    function giftTickets(
        address[] calldata users,
        uint256[] calldata tickets
    ) external onlyAdminOrOwner {
        require(users.length == tickets.length, "KVC: length mismatch");

        //UsersStorage storage uStore = _getUsersStorage();
        for (uint256 i = 0; i < users.length; ++i) {
            _mintTickets(users[i], tickets[i]);
        }
    }

    // ========== Buyback section ==========
    //+
    modifier thenBuybackStarted() {
        StateStorage memory state = _getStateStorage();
        require(state._buybackStarted, "Buyback must be started");
        _;
    }

    //+
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
        onlyOwner
    {
        // thenMilestoneNotReached
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

        uint256 totalCost = 0;
        for (uint256 id = 1; id <= 40; ++id) {
            uint256 balance = balanceOf(to, id);
            if (balance > 0) {
                _burn(to, id, balance);
                totalCost += balance * state._prices[_getTierByTokenId(id)];
            }
        }

        if (totalCost > 0) {
            _sendUsdt(to, totalCost);
            emit Buyback(to, totalCost);
        }
    }

    /// @dev Returns tier by card ID (each tier spans 10 IDs).
    function _getTierByTokenId(uint256 id) private pure returns (uint256) {
        return (id - 1) / 10;
    }

    // ========== Draw section ==========
    //+
    modifier thenDrawStarted() {
        StateStorage memory state = _getStateStorage();
        require(state._drawStarted, "Draw must be started");
        _;
    }

    //+
    modifier thenDrawNotStarted() {
        StateStorage memory state = _getStateStorage();
        require(!state._drawStarted, "Draw started");
        _;
    }

    //+
    function startDraw()
        external
        thenSaleStopped
        thenBuybackNotStarted
        thenDrawNotStarted
        thenMilestoneReached
        onlyOwner
    {
        // thenMilestoneReached
        StateStorage storage state = _getStateStorage();
        state._drawStarted = true;
        emit DrawStarted();
    }

    /// @notice Updates team wallet address.
    function setTeamWallet(address teamWallet_) external onlyOwner {
        require(teamWallet_ != address(0), "KVC: zero team wallet");

        StateStorage storage state = _getStateStorage();
        emit TeamWalletChanged(state._teamWallet, teamWallet_);
        state._teamWallet = teamWallet_;
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

    // TODO
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {}

    // TODO определить победителей сертификата
    // state._buyers >= 1000
    // state._ticketsForCertificate

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Upgradeable, Metadata) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// ?
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
     * @dev Restricts transfers while the contract is paused unless minting or
     * ?burning. Prevents secondary market before `startTrade` is called.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        if (from == address(0)) {
            // Then Mint
        } else {
            if (to == address(0)) {
                // Then Burn
                // TODO Check if not Winner burn win token ids
                return super._update(from, to, ids, values);
            }
            _requireNotPaused();
        }
        return super._update(from, to, ids, values);
    }
}
