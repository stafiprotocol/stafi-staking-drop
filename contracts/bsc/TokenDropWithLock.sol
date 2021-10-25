pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/access/Ownable.sol";
import "./bep/SafeBEP20.sol";

contract TokenDropWithLock is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many stake tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 claimedReward; // Reward that user has claimed
        uint256 currentTotalReward; // The amount minted by user but not yet claimed
        uint256 lastClaimedRewardBlock; // The block where user last claimed the reward
    }

    // Info of each pool.
    struct PoolInfo {
        bool emergencySwitch;
        IBEP20 stakeToken;
        uint256 startBlock;
        uint256 rewardPerBlock;
        uint256 totalReward;
        uint256 leftReward;
        uint256 claimableStartBlock;
        uint256 lockedEndBlock;
        uint256 lastRewardBlock;
        uint256 rewardPerShare;
    }

    address public dropToken;

    // All pools.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes tokens. pid => user address => info
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ClaimReward(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(address _dropToken) public {
        dropToken = _dropToken;
    }

    // Add a new pool
    function add(
        IBEP20 _stakeToken, 
        uint256 _startBlock, 
        uint256 _rewardPerBlock, 
        uint256 _totalReward, 
        uint256 _claimableStartBlock,
        uint256 _lockedEndBlock
    ) public onlyOwner {
        require(_totalReward > _rewardPerBlock, "add: totalReward must be greater than rewardPerBlock");
        require(_claimableStartBlock >= _startBlock, "add: claimableStartBlock must be greater than startBlock");
        require(_lockedEndBlock > _claimableStartBlock, "add: lockedEndBlock must be greater than claimableStartBlock");

        uint256 lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        poolInfo.push(PoolInfo({
            emergencySwitch: true,
            stakeToken: _stakeToken,
            startBlock: _startBlock,
            rewardPerBlock: _rewardPerBlock,
            totalReward: _totalReward,
            leftReward: _totalReward,
            claimableStartBlock: _claimableStartBlock,
            lockedEndBlock: _lockedEndBlock,
            lastRewardBlock: lastRewardBlock,
            rewardPerShare: 0
        }));
    }

    function set(uint256 _pid, bool _emergencySwitch) public onlyOwner {
        poolInfo[_pid].emergencySwitch = _emergencySwitch;
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.emergencySwitch, "updatePool: emergencySwitch closed");

        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 stakeSupply = pool.stakeToken.balanceOf(address(this));
        if (stakeSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 reward = getPoolReward(pool.lastRewardBlock, block.number, pool.rewardPerBlock, pool.leftReward);
        
        if (reward > 0) {
            pool.leftReward = pool.leftReward.sub(reward);
            pool.rewardPerShare = pool.rewardPerShare.add(reward.mul(1e12).div(stakeSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                user.currentTotalReward = user.currentTotalReward.add(pending);
            }
        }
        if (_amount > 0) {
            pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (!pool.emergencySwitch) {
            emergencyWithdraw(_pid);
            return;
        }
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(_amount > 0 && user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            user.currentTotalReward = user.currentTotalReward.add(pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimReward(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(block.number > pool.claimableStartBlock, "claimReward: not start");

        deposit(_pid, 0);

        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.currentTotalReward > 0, "claimReward: no reward to claim");

        uint256 currentClaimedReward = 0;
        if (block.number >= pool.lockedEndBlock) {
            currentClaimedReward = user.currentTotalReward;
        } else {
            uint256 lastClaimedRewardBlock = user.lastClaimedRewardBlock < pool.claimableStartBlock ? pool.claimableStartBlock : user.lastClaimedRewardBlock;
            currentClaimedReward = user.currentTotalReward.mul(block.number.sub(lastClaimedRewardBlock)).div(pool.lockedEndBlock.sub(lastClaimedRewardBlock));
        }

        if (currentClaimedReward > 0) {
            user.currentTotalReward = user.currentTotalReward.sub(currentClaimedReward);
            user.claimedReward = user.claimedReward.add(currentClaimedReward);
            user.lastClaimedRewardBlock = block.number;

            safeTransferReward(msg.sender, currentClaimedReward);
        }

        emit ClaimReward(msg.sender, _pid, currentClaimedReward);
    }

    function safeTransferReward(address _to, uint256 _amount) internal {
        uint256 bal = IBEP20(dropToken).balanceOf(address(this));
        require(bal >= _amount, "balance not enough");
        IBEP20(dropToken).safeTransfer(_to, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "no stake amount");

        pool.stakeToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function getPoolReward(uint256 _from, uint256 _to, uint256 _rewardPerBlock, uint256 _leftReward) public pure returns (uint) {
        uint256 amount = _to.sub(_from).mul(_rewardPerBlock);
        return _leftReward < amount ? _leftReward : amount;
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        uint256 stakeSupply = pool.stakeToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && stakeSupply > 0) {
            uint256 reward = getPoolReward(pool.lastRewardBlock, block.number, pool.rewardPerBlock, pool.leftReward);
            rewardPerShare = rewardPerShare.add(reward.mul(1e12).div(stakeSupply));
        }
        return user.amount.mul(rewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    function getUserClaimableReward(uint _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.claimableStartBlock) {
            return 0;
        }
        uint256 pending = pendingReward(_pid, _user);
        UserInfo storage user = userInfo[_pid][_user];
        uint256 totalReward = user.currentTotalReward.add(pending);
        if (totalReward == 0) {
            return 0;
        }
        if (block.number >= pool.lockedEndBlock) {
            return totalReward;
        }
        uint256 lastClaimedRewardBlock = user.lastClaimedRewardBlock < pool.claimableStartBlock ? pool.claimableStartBlock : user.lastClaimedRewardBlock;

        return totalReward.mul(block.number.sub(lastClaimedRewardBlock)).div(pool.lockedEndBlock.sub(lastClaimedRewardBlock));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
}
