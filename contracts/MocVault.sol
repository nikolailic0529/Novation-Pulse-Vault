// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITefiVault.sol";

interface IStrategy {
    function deposit(uint amount) external;
}

contract MocVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint public underlying;
    address public strategy;
    IERC20 public asset;

    uint public rebalanceRate = 20;
    uint public profits;
    uint public totalLoss;
    uint public totalShare;

    mapping(address => uint) public shares;

    modifier onlyStrategy {
        require (msg.sender == strategy, "!strategy");
        _;
    }

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function setStrategy(address _strategy) external onlyOwner {
        strategy = _strategy;
    }

    function available() public view returns (uint) {
        return asset.balanceOf(address(this));
    }

    function balance() public view returns (uint) {
        return asset.balanceOf(address(this)) + underlying;
    }

    function balanceOf(address _user) public view returns (uint) {
        return totalShare == 0 ? 0 : shares[_user] * balance() / totalShare;
    }

    function deposit(uint _amount) external nonReentrant {
        require (_amount > 0, "!amount");

        uint share;
        uint poolBal = balance();
        if (totalShare == 0) {
            share = _amount;
        } else {
            share = (_amount * totalShare) / poolBal;
        }

        asset.transferFrom(msg.sender, address(this), _amount);

        shares[msg.sender] += share;
        totalShare += share;

        _rebalance();
    }

    function withdraw(uint _share) external nonReentrant {
        require (_share <= shares[msg.sender], "exceeded share");

        uint amount = _share * balance() / totalShare;
        require (amount <= available(), "!enough");

        shares[msg.sender] -= _share;
        totalShare -= _share;

        asset.safeTransfer(msg.sender, amount);
    }

    function reportLoss(uint _loss) external {
        require (_loss <= totalShare / 2, "wrong lose report");
        if (_loss <= profits) {
            profits -= _loss;
        } else {
            totalLoss += (_loss - profits);
            profits = 0;
        }
        underlying -= _loss;
    }

    /// Report profit to Platform
    function reportProfit(uint _profit) external {
        require (asset.balanceOf(msg.sender) >= _profit, "!profit");
        require (asset.allowance(msg.sender, address(this)) >= _profit, "!allowance");

        asset.safeTransferFrom(msg.sender, address(this), _profit);

        if (_profit > totalLoss) {
            profits += (_profit - totalLoss);
            totalLoss = 0;
        } else {
            totalLoss -= _profit;
        }
    }

    function close() external onlyStrategy {
        require (underlying > 0, "!unerlying");
        asset.safeTransferFrom(msg.sender, address(this), underlying);
        underlying = 0;
    }

    /// Manual refill to Platform
    function refill(uint _amount) external onlyStrategy nonReentrant {
        require (_amount <= underlying, "exceeded amount");
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        underlying -= _amount;
    }

    /// Returns amount needed to refill
    function refillable() public view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying;
        uint keepBal = rebalanceRate * poolBal / 100;
        
        if (curBal >= keepBal) return 0;

        return keepBal - curBal;
    }

    function investable() public view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying;
        uint keepBal = rebalanceRate * poolBal / 100;
        
        if (curBal <= keepBal) return 0;

        return curBal - keepBal;
    }

    /// Auto refill the fillable amount
    function autoRefill() external onlyStrategy nonReentrant {
        uint amount = refillable();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        underlying -= amount;
    }

    function rebalance() external nonReentrant {
        _rebalance();
    }
    
    function _rebalance() internal {
        uint invest = investable();
        if (invest == 0) return;
        asset.safeTransfer(strategy, invest);
        underlying += invest;
        IStrategy(strategy).deposit(invest);
    }
}