// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

interface IKingsVaultCards {
    // ──────────────────────────────────────────────────────────────────────
    //                               ERRORS
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Thrown when a zero address is passed for the team wallet.
    error ZeroTeamWallet();

    /// @notice Thrown when a caller is neither admin nor owner.
    error OnlyAdminOrOwner();

    /// @notice Thrown when a tier index is out of allowed range.
    error InvalidTier();

    /// @notice Thrown when quantity is zero.
    error ZeroQuantity();

    /// @notice Thrown when USDT transferFrom fails on buy.
    error PaymentFailed();

    /// @notice Thrown when USDT transfer fails (for sending rewards or buyback).
    error USDTTransferFailed();

    /// @notice Thrown when trying to interact with a sale that must be stopped but is not (or vice versa).
    error SaleMustBeStopped();
    error SaleAlreadyStopped();

    /// @notice Thrown when checking for minimum milestone not reached/reached.
    error MilestoneNotReached();
    error MilestoneReached();

    /// @notice Thrown when checking for buyback state.
    error BuybackMustBeStarted();
    error BuybackAlreadyStarted();

    /// @notice Thrown when checking for draw state.
    error DrawMustBeStarted();
    error DrawAlreadyStarted();

    /// @notice Thrown when winners have or haven't been awarded, but the opposite is required.
    error WinnersNotAwarded();
    error WinnersAlreadyAwarded();

    /// @notice Thrown when the caller attempts to burn a winner token but has none.
    error NotAWinner();

    /// @notice Thrown when array lengths don't match (e.g., in giftTickets).
    error LengthMismatch();

    // ──────────────────────────────────────────────────────────────────────
    //                               STORAGE
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Holds the primary state variables of the contract.
    struct StateStorage {
        bool _saleStopped; // If true, the primary sale is closed permanently.
        bool _buybackStarted; // If true, users can sell their cards back to the contract.
        bool _drawStarted; // If true, the lucky draw process has begun.
        bool _winnersAwarded; // If true, winners for the main prize(s) have already been selected.
    }

    struct CounterStorage {
        uint256 _buyers; // Number of unique buyers who purchased cards.
        uint256 _ticketsForCertificate; // A special cutoff of tickets for certain "certificate" draws (first 1000 buyers).
        uint256 _totalRaised; // Total USDT raised from the primary sale.
        uint256 _totalTeamRewards; // Accumulated team rewards that are not yet claimed.
        uint256 _totalTeamRewardsClaimed; // Amount of team rewards already claimed.
        uint256 _totalRefRewards; // Accumulated referral rewards yet to be claimed.
        uint256 _totalRefRewardsClaimed; // Amount of referral rewards already claimed.
    }

    /// @dev Per-user data, holding their spent amount, referrer, and unclaimed referral rewards.
    struct UserData {
        uint256 _spent; // Total USDT spent on buying cards.
        address _referrer; // Address that referred this user.
        uint256 _refRewards; // Accumulated referral rewards not yet claimed.
    }

    /// @dev Holds all mappings for user-related data, including admin/referrer roles.
    struct UsersStorage {
        address _usdt; // ERC‑20 USDT token address used for payments.
        address _teamWallet; // Address that will receive funds and hold the main wallet privileges.
        mapping(address => UserData) _user;
        mapping(address => bool) _admin;
        mapping(address => bool) _referrer;
    }

    // ──────────────────────────────────────────────────────────────────────
    //                                EVENTS
    // ──────────────────────────────────────────────────────────────────────

    /**
     * @dev Emitted when an admin is added or removed.
     */
    event AdminChanged(address indexed admin, bool indexed status);

    /**
     * @dev Emitted when the team wallet address changes from `prev` to `next`.
     */
    event TeamWalletChanged(address indexed prev, address indexed next);

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
}
