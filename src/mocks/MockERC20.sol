// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev Mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    /**
     * @dev Constructor that gives the specified address an initial supply of tokens.
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Token decimals
     * @param initialSupply Initial token supply
     * @param initialHolder Address to receive the initial supply
     */
    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply, address initialHolder)
        ERC20(name, symbol)
    {
        _decimals = decimals_;
        _mint(initialHolder, initialSupply);
    }

    /**
     * @dev Simple public mint function for testing
     * @param account Address to mint tokens to
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /**
     * @dev Burns tokens from the caller's balance
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Burns tokens from a specified account
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) external {
        _burn(from, amount);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view override returns (uint8 decimals_) {
        decimals_ = _decimals;
    }
}
