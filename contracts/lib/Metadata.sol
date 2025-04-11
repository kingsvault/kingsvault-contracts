// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @title Metadata
 * @dev Abstract contract for managing metadata, including name, symbol, base URI, and royalties.
 *      Utilizes storage slots for efficient storage in upgradeable contracts.
 */
abstract contract Metadata is
    Initializable,
    ERC1155Upgradeable,
    OwnableUpgradeable
{
    using Strings for uint256;

    /**
     * @dev Struct for storing metadata-related information in a storage slot.
     */
    struct MetadataStorage {
        string _name; // Name of the token collection
        string _symbol; // Symbol of the token collection
        string _baseURI; // Base URI for metadata
    }

    /**
     * @dev Storage slot constant for MetadataStorage, computed using keccak256.
     * keccak256(abi.encode(uint256(keccak256("KingsVaultCards.storage.metadata")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant MetadataStorageLocation =
        0xcc940b55fd63d6ffbe37b3e06982f371d55299a99d110340df096abb3f7ed400;

    /**
     * @dev Internal function to retrieve MetadataStorage struct from storage slot.
     */
    function _getMetadataStorage()
        private
        pure
        returns (MetadataStorage storage $)
    {
        assembly {
            $.slot := MetadataStorageLocation
        }
    }

    /// @dev Emitted when the contract URI is updated.
    event ContractURIUpdated(string prevURI, string newURI);

    /**
     * @dev Initializes metadata-related values.
     * @param uri_ Base URI for metadata.
     * @param name_ Name of the token collection.
     * @param symbol_ Symbol of the token collection.
     */
    function __Metadata_init(
        string memory uri_,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        __Metadata_init_unchained(uri_, name_, symbol_);
    }

    /**
     * @dev Initializes metadata-related values.
     * @param uri_ Base URI for metadata.
     * @param name_ Name of the token collection.
     * @param symbol_ Symbol of the token collection.
     */
    function __Metadata_init_unchained(
        string memory uri_,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        MetadataStorage storage $ = _getMetadataStorage();
        $._name = name_;
        $._symbol = symbol_;
        $._baseURI = uri_;
    }

    /**
     * @dev Returns proxy-related details: initialized version, admin, and implementation address.
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

    /**
     * @dev Returns the token collection name.
     */
    function name() external pure returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return $._name;
    }

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external pure returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return $._symbol;
    }

    /**
     * @dev Returns the base URI for metadata.
     */
    function baseURI() external pure returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return $._baseURI;
    }

    /**
     * @dev Updates the base URI for metadata. Only callable by the owner.
     * @param newuri New base URI.
     */
    function setBaseURI(string memory newuri) external onlyOwner {
        string memory prev = contractURI();
        MetadataStorage storage $ = _getMetadataStorage();
        $._baseURI = newuri;
        emit ContractURIUpdated(prev, contractURI());
    }

    /**
     * @dev Returns the full contract URI based on the base URI.
     */
    function contractURI() public pure returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
        return
            bytes($._baseURI).length > 0
                ? string.concat($._baseURI, "contract.json")
                : "";
    }

    /**
     * @dev Returns the metadata URI for a given token ID.
     * @param tokenId Token ID for which to retrieve metadata URI.
     */
    function uri(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        MetadataStorage memory $ = _getMetadataStorage();
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
}
