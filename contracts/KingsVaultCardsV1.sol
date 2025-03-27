// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

interface IMetadata {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);
}

/// @custom:security-contact hi@kingsvault.io
contract KingsVaultCardsV1 is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using Strings for uint256;

    struct MetadataStorage {
        string _name;
        string _symbol;
        string _baseURI;
    }

    // keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.metadata")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MetadataStorageLocation =
        0xcc940b55fd63d6ffbe37b3e06982f371d55299a99d110340df096abb3f7ed400;

    function _getMetadataStorage()
        private
        pure
        returns (MetadataStorage storage $)
    {
        assembly {
            $.slot := MetadataStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _uri,
        address initialOwner,
        address royaltyReceiver,
        uint96 royaltyFee
    ) public virtual initializer {
        __ERC1155_init("");
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC2981_init();
        __Ownable_init(initialOwner);
        __Pausable_init();

        MetadataStorage storage metadata = _getMetadataStorage();
        metadata._name = "Kings Vault Cards";
        metadata._symbol = "KVC";
        metadata._baseURI = _uri;

        _setDefaultRoyalty(royaltyReceiver, royaltyFee);

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

    /**
     * @dev Returns the proxy version, admin, and implementation addresses.
     * This function reads from the storage slots defined by the ERC1967 standard.
     * @return initializedVersion The initialized version of the contract.
     * @return admin The address of the admin.
     * @return implementation The address of the implementation contract.
     */
    function proxy()
        external
        view
        returns (
            uint64 initializedVersion,
            address admin,
            address implementation
        )
    {
        // @openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol
        bytes32 ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return (
            _getInitializedVersion(),
            StorageSlot.getAddressSlot(ADMIN_SLOT).value,
            StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value
        );
    }

    function name() external view virtual returns (string memory) {
        MetadataStorage storage $ = _getMetadataStorage();
        return $._name;
    }

    function symbol() external view virtual returns (string memory) {
        MetadataStorage storage $ = _getMetadataStorage();
        return $._symbol;
    }

    function baseURI() external view virtual returns (string memory) {
        MetadataStorage storage $ = _getMetadataStorage();
        return $._baseURI;
    }

    function setBaseURI(string memory newuri) external onlyOwner {
        MetadataStorage storage $ = _getMetadataStorage();
        $._baseURI = newuri;
    }

    function contractURI() external view virtual returns (string memory) {
        MetadataStorage storage $ = _getMetadataStorage();

        return
            bytes($._baseURI).length > 0
                ? string.concat($._baseURI, "contract.json")
                : "";
    }

    function uri(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        MetadataStorage storage $ = _getMetadataStorage();

        return
            bytes($._baseURI).length > 0
                ? string(
                    abi.encodePacked(
                        $._baseURI,
                        Strings.toString(tokenId),
                        ".json"
                    )
                )
                : "";
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public onlyOwner {
        _mint(account, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function setPause(bool status) external onlyOwner {
        if (status) _pause();
        else _unpause();
    }

    /**
     * @dev Sets the royalty information that all ids in this contract will default to.
     *
     * Requirements:
     * - `receiver` cannot be the zero address.
     * - `feeNumerator` cannot be greater than the fee denominator.
     */
    function setRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
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

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IMetadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
