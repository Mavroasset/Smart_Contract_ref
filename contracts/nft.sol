// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract NodeNFT is ERC721A, ERC721AQueryable, Ownable, AccessControl {
    // Role definitions
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // NFT pricing constants
    uint256 public constant GOLDEN_PRICE = 25; // $25
    uint256 public constant DIAMOND_PRICE = 50; // $50

    // NFT type tracking
    mapping(uint256 => bool) public isGolden;
    mapping(uint256 => bool) public isAngel;
    mapping(address => uint256) public goldenHoldings;
    mapping(address => uint256) public angelHoldings;

    // Base URI for metadata
    string private _baseTokenURI;
    string public goldenTokenUri;
    string public angelTokenUri;

    constructor() ERC721A("NodeNFT", "NNFT") Ownable(msg.sender) {
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // Admin can also mint by default
        _grantRole(MINTER_ROLE, msg.sender);
    }

    // Minting functions with role-based access control
    function mintGolden(address to, uint256 quantity) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "Cannot mint to zero address");
        require(quantity > 0, "Must mint at least one");

        uint256 startTokenId = _nextTokenId();
        _mint(to, quantity);
        
        for (uint256 i = 0; i < quantity; i++) {
            isGolden[startTokenId + i] = true;
        }
        
        goldenHoldings[to] += quantity;
    }

    function mintAngel(address to, uint256 quantity) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "Cannot mint to zero address");
        require(quantity > 0, "Must mint at least one");

        uint256 startTokenId = _nextTokenId();
        _mint(to, quantity);
        
        for (uint256 i = 0; i < quantity; i++) {
            isAngel[startTokenId + i] = true;
        }
        
        angelHoldings[to] += quantity;
    }

    // URI management
    function setBaseURI(string memory baseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = baseURI;
    }

    function setTokenUris(string memory _goldenUri, string memory _angelUri) external onlyRole(ADMIN_ROLE) {
        goldenTokenUri = _goldenUri;
        angelTokenUri = _angelUri;
    }

    function tokenURI(uint256 tokenId) 
        public 
        view 
        virtual 
        override(ERC721A, IERC721A) 
        returns (string memory) 
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (isGolden[tokenId]) {
            return goldenTokenUri;
        } else if (isAngel[tokenId]) {
            return angelTokenUri;
        }

        return "";
    }

    // Role management functions
    function grantMinterRole(address account) external onlyRole(ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, account);
    }

    function revokeMinterRole(address account) external onlyRole(ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, account);
    }

    function grantAdminRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(ADMIN_ROLE, account);
    }

    function revokeAdminRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(ADMIN_ROLE, account);
    }

    // Support for ERC165 interface detection
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, IERC721A, AccessControl)
        returns (bool)
    {
        return 
            ERC721A.supportsInterface(interfaceId) || 
            AccessControl.supportsInterface(interfaceId);
    }

    // Override _startTokenId to start from 1 if desired
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
}