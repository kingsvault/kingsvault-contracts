// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title TransparentUpgradeableProxy
 * @dev This file includes the import of the TransparentUpgradeableProxy contract from OpenZeppelin.
 * The TransparentUpgradeableProxy is a proxy contract that delegates all calls to an implementation address.
 * It allows for upgradeability by allowing the implementation address to be changed.
 * The TransparentUpgradeableProxy uses a proxy admin contract for management, ensuring only the admin can upgrade it.
 *
 * This file does not define any contracts or functions of its own. It merely serves to import the TransparentUpgradeableProxy.
 */
