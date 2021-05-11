pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./WRAToken.sol";

contract WRADrop is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 claimedReward; // Reward that user has claimed
        uint256 currentTotalReward; // The amount minted by user but not yet claimed
    }

    // Info of each pool.
    struct PoolInfo {
        bool emergencySwitch;
        IERC20 lpToken;
        uint256 startBlock;
        uint256 rewardPerBlock;
        uint256 totalReward;
        uint256 leftReward;
        uint256 lastRewardBlock;
        uint256 rewardPerShare;
    }

    WRAToken public WRA;

    // All pools.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens. pid => user address => info
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ClaimReward(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(WRAToken _WRA) public {
        WRA = _WRA;
    }

    // Add a new pool
    function add(
        IERC20 _lpToken, 
        uint256 _startBlock, 
        uint256 _rewardPerBlock, 
        uint256 _totalReward
    ) public onlyOwner {
        require(_totalReward > _rewardPerBlock, "add: totalReward must be greater than rewardPerBlock");

        uint256 lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        poolInfo.push(PoolInfo({
            emergencySwitch: true,
            lpToken: _lpToken,
            startBlock: _startBlock,
            rewardPerBlock: _rewardPerBlock,
            totalReward: _totalReward,
            leftReward: _totalReward,
            lastRewardBlock: lastRewardBlock,
            rewardPerShare: 0
        }));
    }

    function set(uint256 _pid, bool _emergencySwitch) public onlyOwner {
        poolInfo[_pid].emergencySwitch = _emergencySwitch;
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (!pool.emergencySwitch) {
            return;
        }
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 reward = getPoolReward(pool.lastRewardBlock, block.number, pool.rewardPerBlock, pool.leftReward);
        
        if (reward > 0) {
            pool.leftReward = pool.leftReward.sub(reward);
            pool.rewardPerShare = pool.rewardPerShare.add(reward.mul(1e12).div(lpSupply));
        }
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (!pool.emergencySwitch) {
            return;
        }
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.rewardPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                user.currentTotalReward = user.currentTotalReward.add(pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
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
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.rewardPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function claimReward(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.emergencySwitch, "claimReward: emergencySwitch closed");

        deposit(_pid, 0);

        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.currentTotalReward > 0, "claimReward: no reward to claim");

        uint256 currentClaimedReward = user.currentTotalReward;
        
        if (currentClaimedReward > 0) {
            safeTransferReward(msg.sender, currentClaimedReward);
            user.claimedReward = user.claimedReward.add(currentClaimedReward);
            user.currentTotalReward = user.currentTotalReward.sub(currentClaimedReward);
        }

        emit ClaimReward(msg.sender, _pid, currentClaimedReward);
    }

    function safeTransferReward(address _to, uint256 _amount) internal {
        uint256 bal = WRA.balanceOf(address(this));
        if (_amount > bal) {
            WRA.transfer(_to, bal);
        } else {
            WRA.transfer(_to, _amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function getPoolReward(uint256 _from, uint256 _to, uint256 _rewardPerBlock, uint256 _leftReward) public pure returns (uint) {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount = multiplier.mul(_rewardPerBlock);
        return _leftReward < amount ? _leftReward : amount;
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 rewardPerShare = pool.rewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 reward = getPoolReward(pool.lastRewardBlock, block.number, pool.rewardPerBlock, pool.leftReward);
            rewardPerShare = rewardPerShare.add(reward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(rewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    function getUserStakedAmount(uint _pid, address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_pid][_user];
        return user.amount;
    }

    function getUserClaimableReward(uint _pid, address _user) public view returns (uint256) {
        uint256 pending = pendingReward(_pid, _user);
        UserInfo memory user = userInfo[_pid][_user];
        uint256 totalReward = user.currentTotalReward.add(pending);
        return totalReward;
    }

    function getUserClaimedReward(uint _pid, address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_pid][_user];
        return user.claimedReward;
    }

    function getUserCurrentTotalReward(uint _pid, address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_pid][_user];
        uint256 pending = pendingReward(_pid, _user);
        return user.currentTotalReward.add(pending);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPoolLpTokenAddress(uint _pid) public view returns (address) {
        PoolInfo memory pool = poolInfo[_pid];
        return address(pool.lpToken);
    }

    function getPoolLpSupply(uint _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.lpToken.balanceOf(address(this));
    }

    function getPoolStartBlock(uint _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.startBlock;
    }

    function getPoolRewardPerBlock(uint _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.rewardPerBlock;
    }

    function getPoolTotalReward(uint _pid) public view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        return pool.totalReward;
    }
}
