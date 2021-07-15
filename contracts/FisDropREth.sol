pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";

contract FisDropREth is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public FIS;
    bytes32 public merkleRoot;
    uint256 public claimRound;
    bool public claimOpen;

    // This is a packed array of booleans.
    mapping (uint256 => mapping (uint256 => uint256)) private claimedBitMap;
    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 round, uint256 index, address account, uint256 amount);

    constructor(address _FIS) public {
        FIS = _FIS;
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
        claimRound = claimRound.add(1);
        claimOpen = true;
    }

    function openClaim() public onlyOwner {
        claimOpen = true;
    }

    function closeClaim() public onlyOwner {
        claimOpen = false;
    }

    function isClaimed(uint256 round, uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[round][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimRound][claimedWordIndex] = claimedBitMap[claimRound][claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external {
        require(!isClaimed(claimRound, index), 'FisDropREth: already claimed.');
        require(claimOpen, "FisDropREth: claim not open");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'FisDropREth: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        require(IERC20(FIS).transfer(account, amount), 'FisDropREth: Transfer failed.');

        emit Claimed(claimRound, index, account, amount);
    }
}
