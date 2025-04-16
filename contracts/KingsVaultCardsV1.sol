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
import {Tickets} from "./lib/ERC721A/Tickets.sol";
import {TicketsQueryable} from "./lib/ERC721A/TicketsQueryable.sol";
import {IKingsVaultCards} from "./interfaces/IKingsVaultCards.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title KingsVaultCardsV1
 * @notice Main contract for "Kings Vault" collectible cards, implementing ERC-1155 with additional
 *         logic for purchasing, minting, referral rewards, buybacks, draws, etc.
 * @dev Uses upgradeable pattern (Initializable) and Chainlink VRF for random draw functionality.
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
     * @dev Returns a pointer to the StateStorage struct in storage, containing core contract state.
     *      Uses assembly to map a specific storage slot.
     */
    function _getStateStorage() private pure returns (StateStorage storage $) {
        // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.state")) - 1)) & ~bytes32(uint256(0xff))
        assembly {
            $.slot := 0xbc62856e0c02dd21442d34f1898c6a8d302a7437a9cb81bf178895b7cbe27200
        }
    }

    /**
     * @dev Returns a pointer to the CounterStorage struct in storage, tracking numeric counters (like totalRaised).
     *      Uses assembly to map a specific storage slot.
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
     * @dev Returns a pointer to the UsersStorage struct in storage, holding info about users, admins, and referrers.
     *      Uses assembly to map a specific storage slot.
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
        // Prevents implementation contract from being initialized directly
        _disableInitializers();
    }

    /**
     * @notice Contract initializer (replaces constructor for upgradeable pattern).
     * @dev Sets up the initial configuration for the ERC1155 contract, VRF, and other modules.
     * @param initialOwner_   Address of the initial owner/admin.
     * @param usdt_           ERC‑20 USDT token address used for payments.
     * @param teamWallet_     Address that will receive funds and hold the main wallet privileges.
     * @param vrfCoordinator_ Chainlink VRF coordinator address.
     * @param linkToken_      Address of the Chainlink Token contract.
     */
    function initialize(
        address initialOwner_,
        address usdt_,
        address teamWallet_,
        address vrfCoordinator_,
        address linkToken_
    ) public virtual initializer {
        // 1. Initialize ERC1155 with no default URI
        __ERC1155_init();
        __ERC1155Burnable_init();
        __ERC1155Supply_init();

        // 2. Setup Ownership
        __Ownable_init(initialOwner_);

        // 3. Initialize custom modules/libraries
        __Metadata_init(
            "https://kingsvault.github.io/metadata/",
            "Kings Vault Cards",
            "KVC"
        );
        __Tickets_init();
        __TicketsQueryable_init();

        // 4. Chainlink VRF base initialization
        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_, linkToken_);

        _getUsersStorage()._usdt = usdt_;
        _getUsersStorage()._teamWallet = teamWallet_;
        emit TeamWalletChanged(address(0), teamWallet_);

        // Setup admin role for the initial owner
        _getUsersStorage()._admin[initialOwner_] = true;
        emit AdminChanged(initialOwner_, true);
    }

    /**
     * @notice Updates the team wallet address. Cannot be set to zero address.
     * @param teamWallet_ The new address for the team wallet.
     */
    function setTeamWallet(address teamWallet_) external onlyOwner {
        if (teamWallet_ == address(0)) {
            revert ZeroTeamWallet();
        }

        emit TeamWalletChanged(_getUsersStorage()._teamWallet, teamWallet_);
        _getUsersStorage()._teamWallet = teamWallet_;
    }

    /**
     * @dev Example placeholder for USDT token address retrieval.
     */
    function _usdt() private view returns (IERC20) {
        return IERC20(_getUsersStorage()._usdt);
    }

    /**
     * @dev Example placeholder for the team wallet address.
     */
    function _teamWallet() private view returns (address) {
        return _getUsersStorage()._teamWallet;
    }

    /**
     * @dev Denominator for percentage calculations (e.g., 10_000 = 100% in basis points).
     */
    function _fenominator() private pure returns (uint256) {
        return 10_000;
    }

    /**
     * @dev Example function to calculate referral rewards at 5%.
     */
    function _calculateRefRewards(
        uint256 value
    ) private pure returns (uint256) {
        return (value * 500) / _fenominator(); // 5%
    }

    /**
     * @dev Example function to calculate raw team rewards at 20%.
     */
    function _calculateTeamRewardsRaw(
        uint256 value
    ) private pure returns (uint256) {
        return (value * 2_000) / _fenominator(); // 20%
    }

    /**
     * @dev Example function to calculate "car price" portion at 80%.
     */
    function _calculateCarPrice(uint256 value) private pure returns (uint256) {
        return (value * 8_000) / _fenominator(); // 80%
    }

    /**
     * @dev Returns bonus tickets for each tier. For demonstration only.
     *      Tier 0 => 5 tickets, tier 1 => 35, tier 2 => 150, tier 3 => 500.
     */
    function _bonusTickets(
        uint256 tier
    ) private pure returns (uint256 ticketsPerTier) {
        if (tier == 0) return 5;
        else if (tier == 1) return 35;
        else if (tier == 2) return 150;
        else if (tier == 3) return 500;
    }

    /**
     * @dev Example function for retrieving milestone targets.
     *      0 => 75k, 1 => 265k, 2 => 350k (in 18 decimals).
     */
    function _target(uint256 index) private pure returns (uint256 target) {
        if (index == 0) return 75_000_000000000000000000;
        else if (index == 1) return 265_000_000000000000000000;
        else if (index == 2) return 350_000_000000000000000000;
    }

    /**
     * @dev Tiered pricing function, returning 5, 25, 88, 250 USDT for tiers 0..3.
     */
    function _carPriceByTier(
        uint256 tier
    ) private pure returns (uint256 carPrice) {
        if (tier == 0) return 5_000000000000000000;
        else if (tier == 1) return 25_000000000000000000;
        else if (tier == 2) return 88_000000000000000000;
        else if (tier == 3) return 250_000000000000000000;
    }

    /**
     * @dev Helper to read total USDT raised from the CounterStorage.
     */
    function _totalRaised() private view returns (uint256) {
        return _getCounterStorage()._totalRaised;
    }

    /**
     * @dev Determines the "current car price" based on which milestone is reached.
     */
    function _currentCarPrice() private view returns (uint256 carPrice) {
        uint256 totalRaised = _totalRaised();
        if (totalRaised >= _target(2)) return _target(2);
        else if (totalRaised >= _target(1)) return _target(1);
        else if (totalRaised >= _target(0)) return _target(0);
    }

    /**
     * @notice Returns the version of this contract. Useful for upgrades or identification.
     */
    function version() external view virtual returns (string memory) {
        return "1";
    }

    /**
     * @notice Returns a copy of the contract's StateStorage struct (for external reading).
     */
    function getState() external pure returns (StateStorage memory) {
        return _getStateStorage();
    }

    /**
     * @notice Returns a copy of the contract's CounterStorage struct (for external reading).
     */
    function getCounter() external pure returns (CounterStorage memory) {
        return _getCounterStorage();
    }

    /**
     * @notice Returns info about a user: how much they've spent, their referrer, unclaimed refRewards, and tickets.
     * @param wallet Address of the user to query.
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
     * @dev Only an admin or the owner can call functions with this modifier.
     */
    modifier onlyAdminOrOwner() {
        address sender = _msgSender();
        if (!_getUsersStorage()._admin[sender] && sender != owner()) {
            revert OnlyAdminOrOwner();
        }
        _;
    }

    /**
     * @notice Grants or revokes admin status for `wallet`.
     * @param wallet Address to modify admin status.
     * @param status True to set admin, false to remove.
     */
    function setAdmin(address wallet, bool status) external onlyOwner {
        _getUsersStorage()._admin[wallet] = status;
        emit AdminChanged(wallet, status);
    }

    /**
     * @notice Checks if an address is an admin.
     */
    function isAdmin(address wallet) external view returns (bool) {
        return _getUsersStorage()._admin[wallet];
    }

    /**
     * @notice Sets or revokes referrer status for a given address.
     */
    function setReferrer(address wallet, bool status) external onlyOwner {
        _getUsersStorage()._referrer[wallet] = status;
        emit ReferrerChanged(wallet, status);
    }

    /**
     * @notice Checks if a given address is a registered referrer.
     */
    function isReferrer(address wallet) external view returns (bool) {
        return _getUsersStorage()._referrer[wallet];
    }

    // ========== Sale section ==========

    /**
     * @dev Modifier that ensures the primary sale has been explicitly stopped.
     */
    modifier thenSaleStopped() {
        if (!_getStateStorage()._saleStopped) {
            revert SaleMustBeStopped();
        }
        _;
    }

    /**
     * @dev Modifier that ensures the primary sale is still ongoing (not stopped).
     */
    modifier thenSaleNotStopped() {
        if (_getStateStorage()._saleStopped) {
            revert SaleAlreadyStopped();
        }
        _;
    }

    /**
     * @notice Permanently stops new card sales. Cannot be undone.
     */
    function stopSale() external thenSaleNotStopped onlyOwner {
        _getStateStorage()._saleStopped = true;
        emit SaleStopped();
    }

    /**
     * @notice Buys `qty` cards of tier `tier`, minted to caller's address.
     * @param tier Tier index (0..3).
     * @param qty  Quantity to purchase.
     * @param ref  Optional referrer address.
     */
    function buy(uint256 tier, uint256 qty, address ref) external {
        _buyTo(_msgSender(), tier, qty, ref);
    }

    /**
     * @notice Buys `qty` cards for a different address, minted to `to`. Payment is still pulled from msg.sender.
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
     * @dev Core logic for buying cards, transferring USDT, tracking referrals,
     *      computing rewards, and minting the ERC1155 tokens + bonus tickets.
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

        // Price of each card in the chosen tier
        uint256 cost = _carPriceByTier(tier) * qty;
        // Pull USDT from buyer
        bool success = _usdt().transferFrom(_msgSender(), address(this), cost);
        if (!success) {
            revert PaymentFailed();
        }

        // If first time buyer, increment buyer count
        if (uStore._user[to]._spent == 0) {
            counter._buyers++;
        }

        counter._totalRaised += cost;
        // Compute and store referral and team rewards
        uint256 refRewards = _doRefRewards(to, ref, cost);
        _doTeamRewards(to, cost, refRewards);

        // Update user's spent
        uStore._user[to]._spent += cost;

        // Mint actual NFT cards
        for (uint256 i = 0; i < qty; i++) {
            _mint(to, _getRandomTokenId(tier), 1, "");
        }

        // Mint bonus raffle tickets
        uint256 newTickets = _bonusTickets(tier) * qty;
        _mintTickets(to, newTickets);

        // If within first 1000 buyers, track special certificate ticket count
        if (counter._buyers <= 1000) {
            counter._ticketsForCertificate = _ticketsTotal();
        }

        emit Purchase(to, tier, qty, newTickets);
    }

    /**
     * @dev Allocates referral rewards based on a 5% formula, either storing them for later or paying out immediately.
     */
    function _doRefRewards(
        address buyer,
        address ref,
        uint256 cost
    ) private returns (uint256 refRewards) {
        CounterStorage storage counter = _getCounterStorage();
        UsersStorage storage uStore = _getUsersStorage();

        // If the user has a referrer already, override
        if (uStore._user[buyer]._referrer != address(0)) {
            ref = uStore._user[buyer]._referrer;
        }

        // Check if ref is valid and not the same as buyer
        if (!uStore._referrer[ref] || ref == buyer) {
            return 0;
        }

        // If this is buyer's first purchase and ref not set, set it
        if (
            uStore._user[buyer]._spent == 0 &&
            uStore._user[buyer]._referrer == address(0)
        ) {
            uStore._user[buyer]._referrer = ref;
        }

        // 5% referral reward
        refRewards = _calculateRefRewards(cost);
        counter._totalRefRewards += refRewards;

        emit RefRewardsAccrued(ref, buyer, refRewards);

        // If first milestone not reached, store rewards on-chain
        if (_totalRaised() < _target(0)) {
            uStore._user[ref]._refRewards += refRewards;
            return refRewards;
        }

        // Otherwise, pay out ref rewards immediately
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
     * @dev Allocates team rewards (15%, 100%, or partial, depending on milestone).
     */
    function _doTeamRewards(
        address buyer,
        uint256 cost,
        uint256 refRewards
    ) private returns (uint256 teamRewards) {
        CounterStorage storage counter = _getCounterStorage();

        address teamWallet = _teamWallet();
        uint256 totalRaised = _totalRaised();

        // If final target not reached, team = 20% - 5% referral => 15%
        if (totalRaised < _target(2)) {
            teamRewards = _calculateTeamRewardsRaw(cost) - refRewards;
        } else if ((totalRaised - cost) < _target(2)) {
            // If crossing final milestone boundary mid-transaction
            uint256 extra = totalRaised - _target(2);
            uint256 targetDelta = cost - extra;
            teamRewards =
                _calculateTeamRewardsRaw(targetDelta) +
                extra -
                refRewards;
        } else {
            // If final target fully surpassed, team takes entire cost minus ref
            teamRewards = cost - refRewards;
        }

        emit TeamRewardsAccrued(teamWallet, buyer, teamRewards);

        // If first milestone not reached, store on contract
        if (totalRaised < _target(0)) {
            counter._totalTeamRewards += teamRewards;
            return teamRewards;
        }

        // Else pay out immediately
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
     * @dev Transfers USDT from this contract to `to`. Reverts if transfer fails.
     */
    function _sendUsdt(address to, uint256 amount) private {
        bool success = _usdt().transfer(to, amount);
        if (!success) {
            revert USDTTransferFailed();
        }
    }

    /**
     * @dev Generates a pseudo-random token ID within [tier*3 + 1, tier*3 + 3].
     */
    function _getRandomTokenId(uint256 tier) private view returns (uint256) {
        uint256 baseId = tier * 3 + 1;
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    _msgSender(),
                    totalSupply()
                )
            )
        ) % 3; // 0..2
        return baseId + random;
    }

    /**
     * @dev Returns the winner token ID for the final "car" prize: 14, 15, or 16 depending on totalRaised milestone.
     */
    function _getWinnerTokenId() private view returns (uint256) {
        uint256 totalRaised = _totalRaised();
        if (totalRaised >= _target(2)) return 16;
        else if (totalRaised >= _target(1)) return 15;
        else return 14;
    }

    // ========== Milestones Checking ==========

    /**
     * @dev Ensures that the minimum milestone has been reached before allowing the function to proceed.
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

    // ========== Referral Reward Claim ==========

    /**
     * @notice Claims referral rewards for msg.sender, if a milestone is reached.
     */
    function claimRefRewards() external thenMilestoneReached {
        _claimRefRewardsTo(_msgSender());
    }

    /**
     * @notice Batch-claims referral rewards for a list of addresses.
     * @param users Array of addresses to claim for.
     */
    function claimRefRewardsBatch(
        address[] calldata users
    ) external thenMilestoneReached onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _claimRefRewardsTo(users[i]);
        }
    }

    /**
     * @dev Internal function to finalize referral payout to address `to`.
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

    // ========== Team Wallet & Withdrawals ==========

    /**
     * @notice Withdraws accumulated funds to team wallet, once first milestone is reached.
     */
    function withdraw() external thenMilestoneReached onlyOwner {
        CounterStorage storage counter = _getCounterStorage();

        address teamWallet = _teamWallet();
        // sum of all referral rewards (claimed + unclaimed)
        uint256 refRewards = counter._totalRefRewardsClaimed +
            counter._totalRefRewards;

        // "carPrice" depends on highest milestone
        uint256 carPrice = _currentCarPrice();
        uint256 extra = 0;
        // If sale was stopped, leftover is withdrawable
        if (_getStateStorage()._saleStopped) {
            extra = _totalRaised() - carPrice;
        }

        // Team gets 20% of carPrice plus leftover minus portion claimed by ref + team
        uint256 sendAmount = _calculateTeamRewardsRaw(carPrice) +
            extra -
            refRewards -
            counter._totalTeamRewardsClaimed;

        counter._totalTeamRewards = 0;
        counter._totalTeamRewardsClaimed += sendAmount;
        _sendUsdt(teamWallet, sendAmount);
        emit TeamRewardsClaimed(teamWallet, sendAmount);
    }

    // ========== Gift Tickets ==========

    /**
     * @notice Admin function to gift extra raffle tickets to specified users.
     * @param users   Addresses to gift tickets to.
     * @param tickets Corresponding numbers of tickets each user receives.
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

    // ========== Buyback Section ==========

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
     * @notice Starts the buyback phase, letting users sell cards back.
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
     * @notice Sells entire card collection of msg.sender back to contract.
     */
    function buyback() external nonReentrant thenBuybackStarted {
        _buyback(_msgSender());
    }

    /**
     * @notice Batch buyback for multiple users by an admin/owner.
     */
    function buybackBatch(
        address[] calldata users
    ) external nonReentrant thenBuybackStarted onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _buyback(users[i]);
        }
    }

    /**
     * @dev Core buyback logic: for each token ID the user holds, burn and refund USDT.
     */
    function _buyback(address to) private {
        uint256 total = 0;
        // Tiers 0..3 => token IDs [1..12]
        for (uint256 tokenId = 1; tokenId <= 12; ++tokenId) {
            uint256 balance = balanceOf(to, tokenId);
            if (balance > 0) {
                _burn(to, tokenId, balance);
                total += _carPriceByTier(_getTierByTokenId(tokenId)) * balance;
            }
        }

        if (total > 0) {
            _sendUsdt(to, total);
            emit Buyback(to, total);
        }
    }

    /**
     * @dev Helper to derive tier from a tokenId. Each tier spans 3 token IDs.
     */
    function _getTierByTokenId(uint256 tokenId) private pure returns (uint256) {
        return (tokenId - 1) / 3;
    }

    // ========== Draw Section ==========

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
     * @notice Initiates the draw phase after sale is stopped, no buyback is used, and milestone is reached.
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
     * @notice Requests random words from Chainlink VRF to select winners.
     *         Called only once by owner after the draw has started.
     */
    function selectWinners(
        bytes32 keyHash,
        uint64 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit
    ) external thenDrawStarted thenWinnersNotAwarded onlyOwner {
        _vrfCoordinator().requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1
        );
    }

    /**
     * @notice Allows a winner to burn their special token in exchange for the "car" prize in USDT.
     */
    function burnPrize() external nonReentrant thenWinnersAwarded {
        address sender = _msgSender();
        uint256 tokenId = _getWinnerTokenId();
        uint256 balance = balanceOf(sender, tokenId);
        if (balance == 0) {
            revert NotAWinner();
        }

        uint256 sendAmount = _calculateCarPrice(_currentCarPrice());
        _burn(sender, tokenId, balance);
        _sendUsdt(sender, sendAmount);

        emit PrizeCashed(sender, tokenId, sendAmount);
    }

    /**
     * @notice Withdraws unclaimed portion of the car prize if winners do not burn their token.
     */
    function withdrawCarPrice() external thenWinnersAwarded onlyOwner {
        address teamWallet = _teamWallet();
        uint256 sendAmount = _calculateCarPrice(_currentCarPrice());
        _sendUsdt(teamWallet, sendAmount);

        emit PrizeWithdrawn(teamWallet, sendAmount);
    }

    /**
     * @dev Callback from Chainlink VRF providing randomness. Mints winning tokens to randomly selected addresses.
     */
    function _fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override thenDrawStarted thenWinnersNotAwarded {
        address[] memory winners = new address[](4);
        uint256 winnersCounter = 0;
        uint256 iteration = 0;
        uint256 randomWord = randomWords[0];

        // We pick 4 winners total. The first 3 get tokenId 13, the last gets 14..16 depending on totalRaised
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

            // Avoid duplicates in winners array
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
     * @dev Overridden update function that merges logic from ERC1155 and ERC1155Supply for supply tracking.
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
