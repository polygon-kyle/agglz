// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SimpleERC20 is ERC20, Ownable, ERC20Permit {
    // PolygonZkEVM Bridge address
    address public immutable BRIDGE_ADDRESS;

    uint8 private _decimals;

    error NotAuthorized(address sender);

    modifier onlyMinterBurner() {
        if (msg.sender != BRIDGE_ADDRESS && msg.sender != owner()) revert NotAuthorized(msg.sender);
        _;
    }

    constructor(string memory name, string memory symbol, uint8 tokenDecimals, address _bridgeAddress)
        ERC20(name, symbol)
        Ownable(msg.sender)
        ERC20Permit(name)
    {
        BRIDGE_ADDRESS = _bridgeAddress;
        _decimals = tokenDecimals;
    }

    function mint(address to, uint256 amount) public onlyMinterBurner {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public onlyMinterBurner {
        _burn(account, amount);
    }

    function decimals() public view virtual override returns (uint8 tokenDecimals) {
        return _decimals;
    }
}
