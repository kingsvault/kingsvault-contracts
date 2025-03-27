// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

//import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {VRFConsumerBaseV2, VRFCoordinatorV2Interface} from "./lib/VRFConsumerBaseV2.sol";
import {Metadata} from "./lib/Metadata.sol";

/// @custom:security-contact hi@kingsvault.io
contract KingsVaultCardsV1 is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    VRFConsumerBaseV2,
    Metadata
{
    struct ShopStorage {
        string _name;
    }
    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.shop")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ShopStorageLocation =
        0x4f018fdf6283e0e1d6ebb5d4a431134219198655627e2b41f33bc8ba73df0400;

    function _getShopStorage() private pure returns (ShopStorage storage $) {
        assembly {
            $.slot := ShopStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory uri_,
        address initialOwner_,
        address royaltyReceiver_,
        uint96 royaltyFee_,
        address vrfCoordinator_
    ) public virtual initializer {
        __ERC1155_init("");
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC2981_init();
        __Ownable_init(initialOwner_);
        __Pausable_init();

        _pause();

        __VRFConsumerBaseV2_init_unchained(vrfCoordinator_);

        __Metadata_init(
            uri_,
            "Kings Vault Cards",
            "KVC",
            royaltyReceiver_,
            royaltyFee_
        );

        ShopStorage storage shop = _getShopStorage();
    }

    /**
     * @dev Returns the version of the token contract.
     * This can be useful for identifying the deployed version of the contract, especially after upgrades.
     * @return The version string of the contract.
     */
    function version() external view virtual returns (string memory) {
        return "1";
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyOwner {
        _mint(account, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function startTrade() external onlyOwner {
        _unpause();
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
