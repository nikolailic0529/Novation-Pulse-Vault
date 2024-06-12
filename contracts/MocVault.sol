// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

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
    uint public totalSupply;
    uint public totalShare;

    mapping(address => uint) public amounts;
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
        amounts[msg.sender] += _amount;
        totalShare += share;
        totalSupply += _amount;

        _rebalance();
    }

    function withdraw(uint _share) external nonReentrant {
        require (_share <= shares[msg.sender], "exceeded share");

        uint amount = _share * balance() / totalShare;
        require (amount <= available(), "!enough");

        shares[msg.sender] -= _share;
        amounts[msg.sender] -= amount;
        totalShare -= _share;
        totalSupply -= amount;

        asset.safeTransfer(msg.sender, amount);
    }

    function reportLoss(uint _loss) external {
        require (_loss <= totalSupply / 2, "wrong lose report");
        uint toInvest = _loss;
        if (_loss <= profits) {
            profits -= _loss;
        } else {
            toInvest = profits;
            underlying -= (_loss - profits);
            profits = 0;
        }
        if (toInvest > 0) {
            asset.safeTransfer(strategy, toInvest);
            IStrategy(strategy).deposit(toInvest);
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
        uint poolBal = curBal + underlying - profits;
        uint keepBal = rebalanceRate * poolBal / 100 + profits;
        
        if (curBal >= keepBal) return 0;

        return keepBal - curBal;
    }

    function investable() public view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying - profits;
        uint keepBal = rebalanceRate * poolBal / 100 + profits;
        
        if (curBal <= keepBal) return 0;

        return curBal - keepBal;
    }

    function totalLoss() public view returns (uint) {
        uint totalAvailable = underlying + available() - profits;
        return totalSupply > totalAvailable ? (totalSupply - totalAvailable) : 0;
    }

    /// Auto refill the fillable amount
    function autoRefill() external onlyStrategy nonReentrant {
        uint amount = refillable();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        underlying -= amount;
    }

    /// Report profit to Platform
    function payout(uint _amount) external {
        uint _totalLoss = totalLoss();
        uint _payout = _amount;
        if (_payout > _totalLoss) _payout -= _totalLoss;
        else _payout = 0;
        profits += _payout;
        
        if (_payout > 0) {
            asset.safeTransferFrom(msg.sender, address(this), _payout);
        }

        underlying += (_amount - _payout);
    }

    function manualPayout(uint _amount) external nonReentrant {
        uint _totalLoss = totalLoss();
        uint _payout = _amount;
        if (_payout > _totalLoss) _payout -= _totalLoss;
        else _payout = 0;
        profits += _payout;
        
        asset.safeTransferFrom(msg.sender, address(this), _amount);
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