//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IPayoutAgent {
    function payout(address, uint, bool) external;
}

contract TefiVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint amount;
        uint share;
        uint expireAt;
        uint depositedAt;
        uint claimedAt;
    }

    address public strategy;
    IERC20 public asset;
    address public payoutAgent;
    address public constant treasuryWallet = 0x12D16f3A335dfdB575FacE8e3ae6954a1C0e24f1;

    uint public totalSupply;
    uint public totalShare;
    uint public underlying;
    uint public profits;

    mapping(address => UserInfo) public users;
    mapping(address => address) public referrals;
    EnumerableSet.AddressSet userList;
    mapping(address => bool) investWhitelist;
    mapping(address => bool) permanentWhitelist;

    uint public rebalanceRate = 20;
    uint public farmPeriod = 60 days;
    uint public maxSupply = type(uint).max;
    bool public isPublic;

    bool locked;
    uint public constant DUST = 0.1 ether;

    event Deposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event WithdrawnAll(address indexed user, uint amount);
    event Claimed(address indexed user, uint amount);
    event Compounded(address indexed user, uint amount);

    modifier onlyStrategy {
        require (msg.sender == strategy, "!permission");
        _;
    }

    modifier clearDustShare {
        _;
        UserInfo storage user = users[msg.sender];
        if (balanceOf(msg.sender) < DUST) {
            totalSupply -= user.amount;
            totalShare -= user.share;
            delete users[msg.sender];
        }
    }

    modifier updateUserList {
        _;
        if (balanceOf(msg.sender) > 0) {
            if (!userList.contains(msg.sender)) userList.add(msg.sender);
        }
        else if (userList.contains(msg.sender)) userList.remove(msg.sender);
    }


    constructor(address _strategy, address _asset) {
        strategy = _strategy;
        asset = IERC20(_asset);

        asset.approve(payoutAgent, type(uint).max);
    }

    function getUserList() external view returns (address[] memory) {
        return userList.values();
    }

    function userCount() external view returns (uint) {
        return userList.length();
    }

    function myReferredWallets(address _wallet) external view returns (address[] memory) {
        uint count;
        for (uint i = 0; i < userList.length(); i++) {
            address user = userList.at(i);
            if (referrals[user] == _wallet) count++;
        }
        if (count == 0) return new address[](0);

        address[] memory _referrals = new address[](count);
        count = 0;
        for (uint i = 0; i < userList.length(); i++) {
            address user = userList.at(i);
            if (referrals[user] == _wallet) _referrals[count] = user;
            ++count;
        }
        return _referrals;
    }

    function balance() public view returns (uint) {
        return asset.balanceOf(address(this)) + underlying;
    }

    function available() public view returns (uint) {
        return asset.balanceOf(address(this));
    }

    function balanceOf(address _user) public view returns (uint) {
        return users[_user].share * balance() / totalShare;
    }

    function principalOf(address _user) public view returns (uint) {
        UserInfo storage user = users[_user];
        uint curBal = user.share * balance() / totalShare;
        return curBal > user.amount ? user.amount : curBal;
    }

    function earned(address _user) public view returns (uint) {
        UserInfo storage user = users[_user];
        uint bal = balanceOf(_user);
        return user.amount < bal ? (bal - user.amount) : 0;
    }

    function claimable(address _user) public view returns (uint) {
        UserInfo storage user = users[_user];
        uint bal = balanceOf(_user);
        if (user.amount >= bal) return 0;
        uint _earned = bal - user.amount;
        return _calculateExpiredEarning(_earned, user.claimedAt, user.expireAt);
    }

    function totalEarned() external view returns (uint) {
        uint totalBal = balance();
        return totalBal > totalSupply ? (totalBal - totalSupply) : 0;
    }

    function deposit(uint _amount) external whenNotPaused nonReentrant updateUserList {
        require (isPublic || investWhitelist[msg.sender], "!investor");
        require (_amount > 0, "!amount");
        require (balance() - profits + _amount <= maxSupply, "exceeded max supply");

        uint share;
        uint poolBal = balance();
        if (totalShare == 0) {
            share = _amount;
        } else {
            share = (_amount * totalShare) / poolBal;
        }

        asset.transferFrom(msg.sender, address(this), _amount);

        UserInfo storage user = users[msg.sender];
        user.share += share;
        user.amount += _amount;
        totalShare += share;
        totalSupply += _amount;

        if (user.expireAt == 0) {
            user.expireAt = block.timestamp + farmPeriod;
        }

        _rebalance();

        emit Deposited(msg.sender, _amount);
    }

    function withdraw(uint _amount, bool _sellback) external nonReentrant clearDustShare updateUserList {
        UserInfo storage user = users[msg.sender];
        uint principal = principalOf(msg.sender);
        require (principal >= _amount, "exceeded amount");
        require (_amount <= available() - profits, "exceeded withdrawable amount");
        
        uint share = _min((_amount * totalShare / balance()), user.share);

        user.share -= share;
        totalShare -= share;
        user.amount -= _amount;
        totalSupply -= _amount;
        
        // asset.safeTransfer(msg.sender, _amount);
        asset.safeTransfer(treasuryWallet, _amount * 5 / 100);
        _amount = _amount * 95 / 100;
        IPayoutAgent(payoutAgent).payout(msg.sender, _amount, _sellback);

        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll(bool _sellback) external nonReentrant clearDustShare updateUserList {
        UserInfo storage user = users[msg.sender];
        require (user.share > 0, "!balance");

        uint availableEarned = earned(msg.sender);
        uint _earned = _calculateExpiredEarning(availableEarned, user.claimedAt, user.expireAt);
        uint left = availableEarned - _earned;
        
        uint _amount = user.share * balance() / totalShare;
        require (_amount <= available(), "exceeded withdrawable amount");

        totalShare -= user.share;
        totalSupply -= user.amount;
        profits -= _min(profits, _earned);
        delete users[msg.sender];

        uint withdrawalFee = (_amount - availableEarned) * 5 / 100;
        uint profitFee = _earned * 5 / 100;

        address referral = referrals[msg.sender];
        if (referral != address(0)) {
            if (profitFee > 0) asset.safeTransfer(referral, profitFee);
            asset.safeTransfer(treasuryWallet, withdrawalFee);
        } else {
            asset.safeTransfer(treasuryWallet, withdrawalFee + profitFee);
        }
        _amount -= (withdrawalFee + profitFee + left);
        
        // asset.safeTransfer(msg.sender, _amount);
        IPayoutAgent(payoutAgent).payout(msg.sender, _amount, _sellback);

        investWhitelist[msg.sender] = false;

        emit WithdrawnAll(msg.sender, _amount);
    }

    function claim(bool _sellback) external nonReentrant clearDustShare updateUserList {
        UserInfo storage user = users[msg.sender];
        require (user.claimedAt < user.expireAt, "expired");

        uint availableEarned = earned(msg.sender);
        require (availableEarned > 0, "!earned");

        uint _earned = _calculateExpiredEarning(availableEarned, user.claimedAt, user.expireAt);
        
        uint share = _min((availableEarned * totalShare / balance()), user.share);

        user.share -= share;
        user.claimedAt = block.timestamp;
        
        // asset.safeTransfer(msg.sender, _earned);
        address referral = referrals[msg.sender];
        asset.safeTransfer(referral != address(0) ? referral : treasuryWallet, _earned * 5 / 100);
        IPayoutAgent(payoutAgent).payout(msg.sender, _earned * 90 / 100, _sellback);

        profits -= _min(profits, _earned* 95 / 100);

        emit Claimed(msg.sender, _earned * 90 / 100);
    }

    function compound() external nonReentrant {
        UserInfo storage user = users[msg.sender];
        require (user.claimedAt < user.expireAt, "expired");

        uint availableEarned = earned(msg.sender);
        require (availableEarned > 0, "!earned");

        uint _earned = _calculateExpiredEarning(availableEarned, user.claimedAt, user.expireAt);

        address referral = referrals[msg.sender];
        asset.safeTransfer(referral != address(0) ? referral : treasuryWallet, _earned * 5 / 100);

        uint compounded = _earned * 90 / 100;
        uint left = availableEarned - (_earned * 95 / 100);
        uint share = _min((left * totalShare / balance()), user.share);
        
        user.share -= share;        
        user.amount += compounded;
        user.claimedAt = block.timestamp;
        totalSupply += compounded;
        profits -= _min(profits, _earned * 95 / 100);

        _rebalance();

        emit Compounded(msg.sender, compounded);
    }

    function rebalance() external nonReentrant {
        _rebalance();
    }
    
    function _rebalance() internal {
        uint invest = investable();
        if (invest == 0) return;
        asset.safeTransfer(strategy, invest);
        underlying += invest;
    }

    function _calculateExpiredEarning(uint _earned, uint _claimedAt, uint _expireAt) internal view returns (uint) {
        if (_expireAt > block.timestamp) return _earned;
        if (_claimedAt >= _expireAt) return 0;
        return _earned * (_expireAt - _claimedAt) / (block.timestamp - _claimedAt);
    }

    function investable() public view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying - profits;
        uint keepBal = rebalanceRate * poolBal / 100;
        
        if (curBal <= keepBal) return 0;

        return curBal - keepBal;
    }

    function refillable() external view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying - profits;
        uint keepBal = rebalanceRate * poolBal / 100;
        
        if (curBal >= keepBal) return 0;

        return keepBal - curBal;
    }

    function _min(uint x, uint y) internal pure returns (uint) {
        return x > y ? y : x;
    }

    function reportLose(uint _lose) external onlyStrategy {
        require (_lose <= totalSupply / 2, "wrong lose report");
        // totalSupply -= _lose;
        underlying -= _lose;
    }

    function refill(uint _amount) external onlyStrategy {
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        underlying -= _amount;
    }

    function payout(uint _amount) external {
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        profits += _amount;
    }

    function updateFarmPeriod(uint _period) external onlyOwner {
        farmPeriod = _period;
    }
    
    function setRebalanceRate(uint _rate) external onlyOwner {
        require (_rate <= 50, "!rate");
        rebalanceRate = _rate;
    }

    function toggleMode() external onlyOwner {
        isPublic = !isPublic;
    }

    function setInvestors(address[] calldata _wallets, bool _flag) external onlyOwner {
        require (!isPublic, "!private mode");
        for (uint i = 0; i < _wallets.length; i++) {
            investWhitelist[_wallets[i]] = _flag;
        }
    }

    function setReferrals(address[] calldata _wallets, address[] calldata _referrals) external onlyOwner {
        require (_wallets.length == _referrals.length, "!referral sets");
        for (uint i = 0; i < _wallets.length; i++) {
            require (_wallets[i] != _referrals[i], "!referral");
            referrals[_wallets[i]] = _referrals[i];
        }
    }

    function setPermanentWhitelist(address[] calldata _wallets, bool _flag) external onlyOwner {
        require (!isPublic, "!private mode");
        for (uint i = 0; i < _wallets.length; i++) {
            permanentWhitelist[_wallets[i]] = _flag;
        }
    }

    function updatePayoutAgent(address _agent) external onlyOwner {
        require (_agent != address(0), "!agent");
        
        asset.approve(payoutAgent, 0);
        asset.approve(_agent, type(uint).max);
        payoutAgent = _agent;
    }

    function updateStrategy(address _strategy) external onlyOwner {
        require (underlying > 0, "existing underlying amount");
        strategy = _strategy;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}