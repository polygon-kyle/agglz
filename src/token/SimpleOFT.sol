// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleOFT
 * @dev Concrete implementation of OFT with mint capability
 */
contract SimpleOFT is OFT {
    address public immutable LZ_ENDPOINT;
    address public immutable MIGRATOR;

    error NotAuthorized();

    constructor(string memory _name, string memory _symbol, address _lzEndpoint, address _delegate)
        OFT(_name, _symbol, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {
        LZ_ENDPOINT = _lzEndpoint;
        MIGRATOR = msg.sender;
    }

    // Allow minting by the owner or the contract that created this one
    function mint(address _to, uint256 _amount) public {
        if (msg.sender != owner() && msg.sender != address(this) && msg.sender != MIGRATOR) revert NotAuthorized();
        _mint(_to, _amount);
    }
}
