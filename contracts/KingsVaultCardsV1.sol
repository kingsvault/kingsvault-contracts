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

import {Metadata} from "./lib/Metadata.sol";
import {VRFConsumerBaseV2, VRFCoordinatorV2Interface} from "./lib/VRFConsumerBaseV2.sol";
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
    struct StateStorage {
        bool _saleStopped;
        bool _buybackStarted;
        bool _drawStarted;
        address _treasury; //?
        address _usdt;
        uint256 _totalRaised;
        uint256 _totalRefRewards;
        uint256 _refPercentage;
        uint256[] _prices;
        uint256[] _bonusTickets;
        uint256[] _targets;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.state")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StateStorageLocation =
        0xbc62856e0c02dd21442d34f1898c6a8d302a7437a9cb81bf178895b7cbe27200;

    function _getStateStorage() private pure returns (StateStorage storage $) {
        assembly {
            $.slot := StateStorageLocation
        }
    }

    struct DrawStorage {
        address[] _users;
        mapping(address userAddress => bool) _admins;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.draw")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DrawStorageLocation =
        0xe524c1ab749904de8811b3908703254854ab86fe50203701b587cb6b8b7f6000;

    function _getDrawStorage() private pure returns (DrawStorage storage $) {
        assembly {
            $.slot := DrawStorageLocation
        }
    }

    struct UserData {
        uint256 _id;
        address _referrer;
        uint256 _refRewards;
    }

    struct UsersStorage {
        mapping(address userAddress => UserData) _user;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.users")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UsersStorageLocation =
        0xbb2ab92c0b02289376da8cc9149aca642b578a5fcf5bd499c2b16904c1464200;

    function _getUsersStorage() private pure returns (UsersStorage storage $) {
        assembly {
            $.slot := UsersStorageLocation
        }
    }

    event Admin(address indexed user, bool indexed status);
    event Purchase(
        address indexed user,
        uint256 indexed tier,
        uint256 quantity,
        uint256 tickets
    );
    event Buyback(address indexed user, uint256 amount);
    event SaleStopped();
    event BuybackStarted();
    event DrawStarted();
    event TradeStarted();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory uri_,
        address initialOwner_,
        address royaltyReceiver_,
        uint96 royaltyFee_,
        address vrfCoordinator_,
        address usdt_
    ) public virtual initializer {
        __ERC1155_init("");
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC2981_init();
        __Ownable_init(initialOwner_);
        __Pausable_init();

        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_);

        __Metadata_init(
            uri_,
            "Kings Vault Cards",
            "KVC",
            royaltyReceiver_,
            royaltyFee_
        );

        __Tickets_init();
        __TicketsQueryable_init();

        StateStorage storage state = _getStateStorage();
        //state._saleStopped = false;
        //state._buybackStarted = false;

        state._refPercentage = 1000; // 1000/10000 = 0.1 = 10%
        state._usdt = usdt_;
        state._prices = [9_990000, 10_990000, 15_990000, 20_990000];
        state._targets = [75_000_000000, 265_000_000000, 350_000_000000];

        DrawStorage storage draw = _getDrawStorage();
        draw._admins[initialOwner_] = true;
        emit Admin(initialOwner_, true);

        _pause();
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
    modifier onlyAdminOrOwner() {
        address sender = _msgSender();
        DrawStorage storage draw = _getDrawStorage();
        require(
            draw._admins[sender] || sender == owner(),
            "Only admin or owner"
        );
        _;
    }

    //+
    function setAdmin(address userAddress, bool status) external onlyOwner {
        DrawStorage storage draw = _getDrawStorage();
        draw._admins[userAddress] = status;
        emit Admin(userAddress, status);
    }

    // ========== Sale section ==========
    //+
    modifier thenSaleStopped() {
        StateStorage memory state = _getStateStorage();
        require(state._saleStopped, "Sale must be stopped");
        _;
    }

    //+
    modifier thenSaleNotStopped() {
        StateStorage memory state = _getStateStorage();
        require(!state._saleStopped, "Sale stopped");
        _;
    }

    //+
    function stopSale() external thenSaleNotStopped onlyOwner {
        StateStorage storage state = _getStateStorage();
        state._saleStopped = true;
        emit SaleStopped();
    }

    //+
    function buy(
        uint256 tier,
        uint256 quantity,
        address referrer
    ) external nonReentrant thenSaleNotStopped {
        _buyTo(_msgSender(), tier, quantity, referrer);
    }

    //+
    function buyTo(
        address userAddress,
        uint256 tier,
        uint256 quantity,
        address referrer
    ) external {
        _buyTo(userAddress, tier, quantity, referrer);
    }

    function _buyTo(
        address userAddress,
        uint256 tier,
        uint256 quantity,
        address referrer
    ) private {
        require(tier >= 0 && tier < 4, "Invalid item type");

        StateStorage storage state = _getStateStorage();

        uint256 cost = state._prices[tier] * quantity;
        require(
            IERC20(state._usdt).transferFrom(_msgSender(), address(this), cost),
            "Payment failed"
        );
        state._totalRaised += cost;

        if (users._user[referrer]._referrer != address(0)) {
            referrer = users._user[referrer]._referrer;
        } else {
            //
        }

        // TODO Проверить что у пригласившего есть покупки NFT на балансе
        if (referrer != address(0) && referrer != userAddress) {
            uint256 refRewards = (cost * state._refPercentage) / 10000;
            state._totalRefRewards += refRewards;

            UsersStorage storage users = _getUsersStorage();
            users._user[referrer]._refRewards += refRewards;
            // TODO если больше минимальной суммы сборов то можно отправлять.
            /*require(
                IERC20(state._usdt).transfer(referrer, refRewards),
                "Referral transfer failed"
            );*/
        } else {
            /*require(
                IERC20(state._usdt).transfer(treasury, refRewards),
                "Treasury transfer failed"
            );*/
        }

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _getRandomTokenId(tier);
            _mint(userAddress, tokenId, quantity, "");
        }

        uint256 newTickets = state._bonusTickets[tier] * quantity;
        _mintTickets(userAddress, newTickets);
        //_nextTicketId()
        //for (uint256 i = 0; i < newTickets; i++) {
        //participants.push(userAddress);
        //purchases[userAddress].ticketNumbers.push(participants.length - 1);
        // TODO event
        //}

        emit Purchase(userAddress, tier, quantity, newTickets);
        // Если больше 1000 то фиксируем количество билетов
    }

    //+
    function _getRandomTokenId(uint256 tier) private view returns (uint256) {
        uint256 baseId = tier * 10 + 1;
        return
            baseId +
            (uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        block.timestamp,
                        _msgSender(),
                        totalSupply()
                    )
                )
            ) % 10);
    }

    function giftTickets(
        address[] calldata users,
        uint256[] calldata tickets
    ) external onlyAdminOrOwner {
        require(users.length == tickets.length, "Parameters mismatch");
        // до 1к пользователей нельзя подарить токены.

        DrawStorage storage draw = _getDrawStorage();
        for (uint256 i = 0; i < users.length; ++i) {
            //draw._users[users[i]]._tickets.
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

    //+
    function startBuyback()
        external
        thenSaleStopped
        thenDrawNotStarted
        thenBuybackNotStarted
        onlyOwner
    {
        StateStorage storage state = _getStateStorage();
        state._buybackStarted = true;
        emit BuybackStarted();
    }

    //+
    function buyback() external nonReentrant thenBuybackStarted {
        _buyback(_msgSender());
    }

    //+
    function buybackBatch(
        address[] calldata users
    ) external nonReentrant thenBuybackStarted onlyAdminOrOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            _buyback(users[i]);
        }
    }

    //+
    function _buyback(address userAddress) private {
        StateStorage memory state = _getStateStorage();

        uint256 totalCost = 0;
        for (uint256 id = 1; id <= 40; ++id) {
            uint256 balance = balanceOf(userAddress, id);
            if (balance > 0) {
                _burn(userAddress, id, balance);
                totalCost += balance * state._prices[_getTierByTokenId(id)];
            }
        }

        require(
            IERC20(state._usdt).transfer(userAddress, totalCost),
            "Buyback failed"
        );
        emit Buyback(userAddress, totalCost);
    }

    //+
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
        onlyOwner
    {
        StateStorage storage state = _getStateStorage();
        state._drawStarted = true;
        emit DrawStarted();
    }

    // TODO claimRefRewards() {}
    // TODO withdraw() {}

    // ========== Draw section ended. ==========

    //+
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

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Upgradeable, Metadata) returns (bool) {
        return super.supportsInterface(interfaceId);
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
