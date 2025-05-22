// SPDX-License-Identifier: GPL-3.0
// Implementation of permit based on https://github.com/WETH10/WETH10/blob/main/contracts/WETH10.sol
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenWrapped is ERC20 {
    // Domain typehash
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    // Permit typehash
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Version
    string public constant VERSION = "1";

    // Chain id on deployment
    uint256 public immutable DEPLOYMENT_CHAIN_ID;

    // Domain separator calculated on deployment
    bytes32 private immutable _DEPLOYMENT_DOMAIN_SEPARATOR;

    // PolygonZkEVM Bridge address
    address public immutable BRIDGE_ADDRESS;

    // Migrator address
    address public immutable MIGRATOR;

    // Decimals
    uint8 private immutable _DECIMALS;

    // Permit nonces
    mapping(address owner => uint256 nonce) public nonces;

    error NotAuthorized(address sender);
    error PermitExpired(uint256 currentTimestamp, uint256 deadline);
    error InvalidSignature(address signer, address owner);

    modifier onlyBridge() {
        if (msg.sender != BRIDGE_ADDRESS && msg.sender != MIGRATOR) revert NotAuthorized(msg.sender);
        _;
    }

    constructor(string memory name, string memory symbol, uint8 __decimals, address _bridgeAddress)
        ERC20(name, symbol)
    {
        BRIDGE_ADDRESS = _bridgeAddress;
        MIGRATOR = msg.sender;
        _DECIMALS = __decimals;
        DEPLOYMENT_CHAIN_ID = block.chainid;
        _DEPLOYMENT_DOMAIN_SEPARATOR = _calculateDomainSeparator(block.chainid);
    }

    function mint(address to, uint256 value) external onlyBridge {
        _mint(to, value);
    }

    // Notice that is not require to approve wrapped tokens to use the bridge
    function burn(address account, uint256 value) external onlyBridge {
        _burn(account, value);
    }

    // Permit relative functions
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        if (block.timestamp > deadline) revert PermitExpired(block.timestamp, deadline);

        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));

        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0) || signer != owner) revert InvalidSignature(signer, owner);

        _approve(owner, spender, value);
    }

    function decimals() public view virtual override returns (uint8 _decimals) {
        _decimals = _DECIMALS;
    }

    /// @dev Return the DOMAIN_SEPARATOR.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view returns (bytes32 domainSeparator) {
        domainSeparator = block.chainid == DEPLOYMENT_CHAIN_ID
            ? _DEPLOYMENT_DOMAIN_SEPARATOR
            : _calculateDomainSeparator(block.chainid);
    }

    /**
     * @notice Calculate domain separator, given a chainID.
     * @param chainId Current chainID
     */
    function _calculateDomainSeparator(uint256 chainId) private view returns (bytes32 domainSeparator) {
        domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), keccak256(bytes(VERSION)), chainId, address(this))
        );
    }
}
