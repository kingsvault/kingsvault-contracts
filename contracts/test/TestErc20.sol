// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title TestErc20
 * @dev Implementation of a customizable ERC20 token with burnable and permit functionality.
 * Inherits from OpenZeppelin's ERC20, ERC20Burnable, and ERC20Permit.
 */
contract TestErc20 is ERC20, ERC20Burnable, ERC20Permit {
    /// @dev Private variable to store the number of decimals for the token.
    uint8 private _decimals;

    /**
     * @dev Constructor that initializes the ERC20 token with a name, symbol, decimals, and total supply.
     * Mints the total supply to the deployer's address.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     * @param decimals_ The number of decimals the token uses.
     * @param totalSupply_ The total supply of tokens to be minted (in whole units).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _decimals = decimals_;
        _mint(_msgSender(), totalSupply_);
    }

    /**
     * @dev Returns the number of decimals used to get the token's user representation.
     * Overrides the default `decimals` function of the ERC20 standard.
     * @return The number of decimals.
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
