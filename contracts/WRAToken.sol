pragma solidity 0.6.12;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract WRAToken is ERC20("WrapFi", "WRA"), Ownable {
    using SafeMath for uint256;

    uint256 public NUMBER_BLOCKS_PER_YEAR;
    uint256 public startAtBlock;

    uint256 public maxTotalSupply = 100000000e18;
    uint256 public genesisLaunchRatio = 10;

    address public genesisLaunchAddress;
    address public stakingReserveAddress;
    address public wrapFiUsersAddress;
    address public devFundAddress;
    address public ecoFundAddress;

    mapping (address => mapping (uint256 => bool)) public mintResult;
    mapping (address => mapping (uint256 => uint256)) public mintInfo;

    constructor(
        uint256 _numberBlocksPerYear,
        address _genesisLaunchAddress,
        address _stakingReserveAddress,
        address _wrapFiUsersAddress,
        address _devFundAddress,
        address _ecoFundAddress) public {
        NUMBER_BLOCKS_PER_YEAR = _numberBlocksPerYear > 0 ? _numberBlocksPerYear : 2102400;
        genesisLaunchAddress = _genesisLaunchAddress;
        stakingReserveAddress = _stakingReserveAddress;
        wrapFiUsersAddress = _wrapFiUsersAddress;
        devFundAddress = _devFundAddress;
        ecoFundAddress = _ecoFundAddress;
        startAtBlock = block.number;
        initMintInfo();
        mintForGenesisLaunch();
        mintForStakingReserve();
        mintForWrapFiUsers();
        mintForDevFund();
        mintForEcoFund();
    }

    function initMintInfo() internal {
        mintInfo[stakingReserveAddress][0] = 60;
        mintInfo[stakingReserveAddress][1] = 45;
        mintInfo[stakingReserveAddress][2] = 30;
        mintInfo[stakingReserveAddress][3] = 15;

        mintInfo[wrapFiUsersAddress][0] = 280;
        mintInfo[wrapFiUsersAddress][1] = 210;
        mintInfo[wrapFiUsersAddress][2] = 140;
        mintInfo[wrapFiUsersAddress][3] = 70;

        mintInfo[devFundAddress][0] = 40;
        mintInfo[devFundAddress][1] = 30;
        mintInfo[devFundAddress][2] = 20;
        mintInfo[devFundAddress][3] = 10;

        mintInfo[ecoFundAddress][0] = 20;
        mintInfo[ecoFundAddress][1] = 15;
        mintInfo[ecoFundAddress][2] = 10;
        mintInfo[ecoFundAddress][3] = 5;
    }

    function mintForGenesisLaunch() private {
        uint256 amount = maxTotalSupply.mul(genesisLaunchRatio).div(100);
        _mint(genesisLaunchAddress, amount);
    }

    function mintForStakingReserve() public onlyOwner {
        mintFor(stakingReserveAddress);
    }

    function mintForWrapFiUsers() public onlyOwner {
        mintFor(wrapFiUsersAddress);
    }

    function mintForDevFund() public onlyOwner {
        mintFor(devFundAddress);
    }

    function mintForEcoFund() public onlyOwner {
        mintFor(ecoFundAddress);
    }

    function mintFor(address _to) private {
        uint256 blockNow = block.number;
        uint256 yearNow = blockNow.sub(startAtBlock).div(NUMBER_BLOCKS_PER_YEAR);
        require(yearNow < 4, "unlock year reach limit");
        require(!mintResult[_to][yearNow], "has mint this year");

        mintResult[_to][yearNow] = true;
        _mint(_to, maxTotalSupply.mul(mintInfo[_to][yearNow]).div(1000));
    }
}