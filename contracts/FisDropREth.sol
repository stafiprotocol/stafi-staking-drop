pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./utils/SafeCast.sol";

contract FisDropREth is Ownable {
    using SafeCast for *;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public FIS;
    bytes32 public merkleRoot;
    uint256 public claimRound;
    bool public claimOpen;
    // This is a packed array of booleans.
    mapping (uint256 => mapping (uint256 => uint256)) private claimedBitMap;
    mapping (bytes32 => bool) public dateDrop;
    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 round, uint256 index, address account, uint256 amount);


    //dropper
    enum ProposalStatus {Inactive, Active, Executed}

    struct Proposal {
        ProposalStatus _status;
        uint40 _yesVotes;      // bitmap, 40 maximum votes
        uint8 _yesVotesTotal;
    }
    mapping(bytes32 => Proposal) public _proposals;
    uint8   public _threshold;

    EnumerableSet.AddressSet droppers;
    modifier onlyDropper{
        require(droppers.contains(msg.sender));
        _;
    }
    function addDropper(address dropper) public onlyOwner{
        droppers.add(dropper);
    }
    
    function removeDropper(address dropper) public onlyOwner{
        droppers.remove(dropper);
    }

    function getDropperIndex(address dropper) public view returns (uint256) {
        return droppers._inner._indexes[bytes32(uint256(dropper))];
    }
    
    function dropperBit(address dropper) private view returns(uint) {
        return uint(1) << getDropperIndex(dropper).sub(1);
    }

    function _hasVoted(Proposal memory proposal, address dropper) private view returns(bool) {
        return (dropperBit(dropper) & uint(proposal._yesVotes)) > 0;
    }

    function changeThreshold(uint256 newThreshold) external onlyOwner {
        _threshold = newThreshold.toUint8();
    }

    constructor(address _FIS, address[] memory initialDroppers, uint256 initialThreshold) public {
        FIS = _FIS;
        _threshold = initialThreshold.toUint8();
        uint256 initialDropperCount = initialDroppers.length;
        for (uint256 i; i < initialDropperCount; i++) {
            droppers.add(initialDroppers[i]);
        }
    }

    function setMerkleRoot(bytes32 dateHash, bytes32 _merkleRoot) public onlyDropper {
        bytes32 dataHash = keccak256(abi.encodePacked(dateHash, _merkleRoot));
        Proposal memory proposal = _proposals[dataHash];

        require(!dateDrop[dateHash],"this date has drop");
        require(uint(proposal._status) <= 1, "proposal already executed/cancelled");
        require(!_hasVoted(proposal, msg.sender), "relayer already voted");
        
        if (proposal._status == ProposalStatus.Inactive) {
            proposal = Proposal({
                    _status : ProposalStatus.Active,
                    _yesVotes : 0,
                    _yesVotesTotal : 0
                });
        }
        proposal._yesVotes = (proposal._yesVotes | dropperBit(msg.sender)).toUint40();
        proposal._yesVotesTotal++; 

        // Finalize if Threshold has been reached
        if (proposal._yesVotesTotal >= _threshold) {
            proposal._status = ProposalStatus.Executed;
            
            merkleRoot = _merkleRoot;
            claimRound = claimRound.add(1);
            claimOpen = true;
            dateDrop[dateHash] = true;
        }
        _proposals[dataHash] = proposal;
    }

    function openClaim() public onlyDropper {
        bytes32 dataHash = keccak256(abi.encodePacked("open", claimRound));
        Proposal memory proposal = _proposals[dataHash];

        require(uint(proposal._status) <= 1, "proposal already executed/cancelled");
        require(!_hasVoted(proposal, msg.sender), "relayer already voted");
        
        if (proposal._status == ProposalStatus.Inactive) {
            proposal = Proposal({
                    _status : ProposalStatus.Active,
                    _yesVotes : 0,
                    _yesVotesTotal : 0
                });
        }
        proposal._yesVotes = (proposal._yesVotes | dropperBit(msg.sender)).toUint40();
        proposal._yesVotesTotal++; 

        // Finalize if Threshold has been reached
        if (proposal._yesVotesTotal >= _threshold) {
            proposal._status = ProposalStatus.Executed;
            claimOpen = true;
        }
        _proposals[dataHash] = proposal;
    }

    function closeClaim() public onlyDropper {
        bytes32 dataHash = keccak256(abi.encodePacked("close", claimRound));
        Proposal memory proposal = _proposals[dataHash];

        require(uint(proposal._status) <= 1, "proposal already executed/cancelled");
        require(!_hasVoted(proposal, msg.sender), "relayer already voted");

        if (proposal._status == ProposalStatus.Inactive) {
            proposal = Proposal({
                    _status : ProposalStatus.Active,
                    _yesVotes : 0,
                    _yesVotesTotal : 0
                });
        }
        proposal._yesVotes = (proposal._yesVotes | dropperBit(msg.sender)).toUint40();
        proposal._yesVotesTotal++; 

        // Finalize if Threshold has been reached
        if (proposal._yesVotesTotal >= _threshold) {
            proposal._status = ProposalStatus.Executed;
            claimOpen = false;
        }
        _proposals[dataHash] = proposal;
    }

    function switchClaim() public onlyOwner {
        claimOpen = !claimOpen;
    }
    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
        claimRound = claimRound.add(1);
        claimOpen = true;
    }

    function withdrawFis(address user, uint256 amount) public onlyOwner{
        IERC20(FIS).transfer(user, amount);
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
