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

interface IStrategy {
    function deposit(uint amount) external;
}

interface IVault {
    function userCount() external view returns (uint);
    function getUserList() external view returns (address[] memory);
    function users(address) external view returns (
        uint amount,
        uint share,
        uint expireAt,
        uint depositedAt,
        uint claimedAt
    );
    function underlying() external view returns (uint);
    function totalSupply() external view returns (uint);
    function totalShare() external view returns (uint);
    function profits() external view returns (uint);
    function totalProfits() external view returns (uint);
    function totalLoss() external view returns (uint);
    function referrals(address) external view returns (address);
    function invested(address) external view returns (bool);
    function investWhitelist(address) external view returns (bool);
    function permanentWhitelist(address) external view returns (bool);
    function vipWhitelist(address) external view returns (bool);
    function eliteWhitelist(address) external view returns (bool);
}

contract PulseVault is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint amount;
        uint prevAmount;
        uint share;
        uint prevShare;
        uint expireAt;
        uint depositedAt;
        uint claimedAt;
    }

    address public strategy;
    IERC20 public asset;
    address public payoutAgent;
    address public treasuryWallet = 0x4734ca96314F0539E0d0D62FcEBc28dBF39F05C9;
    address public reserveWallet = 0x55A6Eed07D656e340eFAd9291de26f0e31c4E962;

    uint public totalSupply;
    uint public totalShare;
    uint public underlying;
    uint public profits;
    uint public totalProfits;
    uint public totalLoss;
    mapping (uint => uint) public dailyProfit;
    mapping (uint => uint) public dailyLoss;

    mapping(address => UserInfo) public users;
    mapping(address => address) public referrals;
    EnumerableSet.AddressSet userList;
    mapping(address => bool) public invested;
    mapping(address => bool) public investWhitelist;
    mapping(address => bool) public permanentWhitelist;
    mapping(address => bool) public vipWhitelist;
    mapping(address => bool) public eliteWhitelist;
    mapping(address => bool) public agents;

    uint public rebalanceRate = 15;
    uint public farmPeriod = 80 days;
    uint public farmVipPeriod = 110 days;
    uint public expireDelta = 2 days;
    uint public maxSupply = type(uint).max;
    uint public maxUserSupply = 100_000 ether;
    uint public maxVipSupply = 500_000 ether;
    bool public isPublic;

    uint public withdrawalFee;     // zero in default
    uint public claimFee = 5;
    uint public referralFee = 3;
    address[] pendings;

    bool public lockedWithdrawal;
    bool locked;
    uint public constant DUST = 0.1 ether;

    event Deposited(address indexed user, uint amount);
    event BulkDeposited(address indexed user, uint amount);
    event Withdrawn(address indexed user, uint amount);
    event WithdrawnAll(address indexed user, uint amount);
    event Claimed(address indexed user, uint amount);
    event Compounded(address indexed user, uint amount);

    event Lost(uint amount);
    event Payout(uint profit);
    event Refilled(uint amount);

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

            if (!permanentWhitelist[msg.sender] && !vipWhitelist[msg.sender] && !eliteWhitelist[msg.sender]) {
                investWhitelist[msg.sender] = false;
            }
        }
    }

    modifier updateUserList {
        _;
        if (balanceOf(msg.sender) > 0) {
            if (!userList.contains(msg.sender)) userList.add(msg.sender);
        }
        else if (userList.contains(msg.sender)) userList.remove(msg.sender);
    }


    constructor(address _strategy, address _asset, address _payoutAgent) {
        strategy = _strategy;
        asset = IERC20(_asset);
        payoutAgent = _payoutAgent;

        asset.approve(payoutAgent, type(uint).max);

        _pause();
    }

    function getUserList() external view returns (address[] memory) {
        return userList.values();
    }

    function userCount() external view returns (uint) {
        return userList.length();
    }

    function referredWallets(address _wallet) external view returns (address[] memory) {
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

    function canBeRefered(address _wallet) external view returns(bool) {
        return invested[_wallet];
    }

    function balance() public view returns (uint) {
        return asset.balanceOf(address(this)) + underlying;
    }

    function available() public view returns (uint) {
        return asset.balanceOf(address(this));
    }

    function balanceOf(address _user) public view returns (uint) {
        return totalShare == 0 ? 0 : users[_user].share * balance() / totalShare;
    }

    function principalOf(address _user) public view returns (uint) {
        if (totalShare == 0) return 0;
        UserInfo storage user = users[_user];
        uint curBal = user.share * balance() / totalShare;
        return curBal > user.amount ? user.amount : curBal;
    }

    function lossOf(address _user) public view returns (uint) {
        if (totalShare == 0) return 0;
        UserInfo storage user = users[_user];
        uint curBal = user.share * balance() / totalShare;
        return curBal < user.amount ? (user.amount - curBal) : 0;
    }

    function earned(address _user) public view returns (uint) {
        UserInfo storage user = users[_user];
        uint amount = user.amount;
        uint share = user.share;
        uint _totalSupply = totalSupply;
        uint _totalShare = totalShare;
        
        if (_isPending(_user) && user.amount > user.prevAmount
        ) {
            share = user.prevShare;
            amount = user.prevAmount;
            _totalSupply = totalSupply - user.amount + amount;
            _totalShare = totalShare - user.share + share;
        }

        // uint bal = balanceOf(_user);
        uint bal = share * (balance() - user.amount + amount) / _totalShare;
        uint _earned = amount < bal ? (bal - amount) : 0;
        uint _maxSupply = vipWhitelist[_user] ? maxVipSupply : maxUserSupply;
        if (amount > _maxSupply) return _earned * _maxSupply / amount;
        return _earned;
    }

    function claimable(address _user) public view returns (uint) {
        return _calculateExpiredEarning(_user);
    }

    function totalEarned() external view returns (uint) {
        uint totalBal = balance();
        return totalBal > totalSupply ? (totalBal - totalSupply) : 0;
    }

    function todayProfit() external view returns (uint) {
        return dailyProfit[block.timestamp / 1 days * 1 days];
    }

    function todayLoss() external view returns (uint) {
        return dailyLoss[block.timestamp / 1 days * 1 days];
    }

    function checkExpiredUsers() external view returns (uint, address[] memory) {
        uint count;
        for (uint i = 0; i < userList.length(); i++) {
            if (users[userList.at(i)].expireAt + expireDelta <= block.timestamp) count++;
        }
        if (count == 0) return (0, new address[](0));
        address[] memory wallets = new address[](count);
        count = 0;
        for (uint i = 0; i < userList.length(); i++) {
            address wallet = userList.at(i);
            if (users[wallet].expireAt + expireDelta <= block.timestamp) {
                wallets[count] = wallet;
                count++;
            }
        }
        return (wallets.length, wallets);
    }

    function bulkDeposit(address[] calldata _users, uint[] calldata _amounts) external nonReentrant {
        require (agents[msg.sender] == true, "!agent");
        require (_users.length == _amounts.length, "!sets");

        uint totalAmount;
        uint _totalShare = totalShare;
        uint poolBal = balance();
        for (uint i = 0; i < _users.length;) {
            uint _amount = _amounts[i];
            address _user = _users[i];
            UserInfo storage user = users[_user];
            bool isVip = vipWhitelist[_user];
            require (_amount > 0, "!amount");

            uint share;
            if (_totalShare == 0) {
                share = _amount;
            } else {
                share = (_amount * _totalShare) / poolBal;
            }

            require (user.amount + _amount <= (isVip ? maxVipSupply : maxUserSupply), "exeeded user max supply");

            if (user.depositedAt == 0) user.depositedAt = block.timestamp;
            pendings.push(_user);

            user.prevAmount = user.amount;
            user.prevShare = user.share;
            user.share += share;
            user.amount += _amount;
            investWhitelist[_user] = true;

            if (user.expireAt == 0) {
                user.expireAt = block.timestamp + (isVip ? farmVipPeriod : farmPeriod);
            }

            if (!invested[_user]) invested[_user] = true;

            if (!userList.contains(_user)) userList.add(_user);

            poolBal += _amount;
            totalAmount += _amount;
            _totalShare += share;
            ++i;
        }

        asset.transferFrom(msg.sender, address(this), totalAmount);

        totalSupply += totalAmount;
        totalShare = _totalShare;

        _rebalance();

        emit BulkDeposited(msg.sender, totalAmount);
    }

    function deposit(uint _amount) external whenNotPaused nonReentrant updateUserList {
        UserInfo storage user = users[msg.sender];
        bool isVip = vipWhitelist[msg.sender];
        require (isPublic || investWhitelist[msg.sender], "!investor");
        require (
            user.share == 0 || 
            permanentWhitelist[msg.sender] ||
            user.claimedAt < user.expireAt, 
            "expired"
        );
        require (_amount > 0, "!amount");
        require (user.amount + _amount <= (isVip ? maxVipSupply : maxUserSupply), "exeeded user max supply");
        require (totalSupply + _amount <= maxSupply, "exceeded max supply");

        uint share;
        uint poolBal = balance();
        if (totalShare == 0) {
            share = _amount;
        } else {
            share = (_amount * totalShare) / poolBal;
        }

        asset.transferFrom(msg.sender, address(this), _amount);

        if (user.depositedAt == 0) user.depositedAt = block.timestamp;
        pendings.push(msg.sender);

        user.prevAmount = user.amount;
        user.prevShare = user.share;
        user.share += share;
        user.amount += _amount;
        totalShare += share;
        totalSupply += _amount;

        if (user.expireAt == 0) {
            user.expireAt = block.timestamp + (isVip ? farmVipPeriod : farmPeriod);
            user.claimedAt = block.timestamp;
        }

        if (!invested[msg.sender]) invested[msg.sender] = true;

        _rebalance();

        emit Deposited(msg.sender, _amount);
    }

    function withdraw(uint _amount, bool _sellback) external nonReentrant updateUserList clearDustShare {
        require (!lockedWithdrawal, "locked withdrawal");
        UserInfo storage user = users[msg.sender];
        uint principal = principalOf(msg.sender);
        require (principal >= _amount, "exceeded amount");
        require (_amount <= available(), "exceeded withdrawable amount");
        
        uint share = _min((_amount * totalShare / balance()), user.share);

        user.share -= share;
        totalShare -= share;
        user.amount -= _amount;
        totalSupply -= _amount;
        
        if (withdrawalFee > 0) {
            asset.safeTransfer(treasuryWallet, _amount * withdrawalFee / 100);
        }
        _amount = _amount * (100 - withdrawalFee) / 100;
        IPayoutAgent(payoutAgent).payout(msg.sender, _amount, _sellback);

        emit Withdrawn(msg.sender, _amount);
    }

    function withdrawAll(bool _sellback) external nonReentrant updateUserList {
        require (!lockedWithdrawal, "locked withdrawal");
        _withdrawAll(msg.sender, _sellback);
    }

    function _withdrawAll(address _user, bool _sellback) internal {
        UserInfo storage user = users[_user];
        require (user.share > 0, "!balance");

        uint availableEarned = earned(_user);
        uint _earned = _calculateExpiredEarning(_user);
        uint left = availableEarned - _earned;
        
        uint _amount = user.share * balance() / totalShare;
        require (_amount - availableEarned <= available(), "exceeded withdrawable amount");

        totalShare -= user.share;
        totalSupply -= user.amount;
        profits -= _min(profits, availableEarned);
        delete users[_user];

        uint _withdrawalFee = (_amount - availableEarned) * withdrawalFee / 100;
        uint _claimFee = _earned * claimFee / 100;
        uint _referralFee = _earned * referralFee / 100;
        address referral = referrals[_user];

        if (_claimFee + _withdrawalFee > 0) {
            asset.safeTransfer(treasuryWallet, _claimFee + _withdrawalFee);
        }
        if (_referralFee > 0) {
            asset.safeTransfer(referral != address(0) ? referral : reserveWallet, _referralFee);
        }
        if (left > 0) asset.safeTransfer(reserveWallet, left);

        _amount -= (_withdrawalFee + _claimFee + _referralFee + left);
        
        IPayoutAgent(payoutAgent).payout(_user, _amount, _sellback);

        if (!permanentWhitelist[_user] && !vipWhitelist[_user] && !eliteWhitelist[_user]) {
            investWhitelist[_user] = false;
        }

        emit WithdrawnAll(_user, _amount);
    }

    function claim(bool _sellback) external nonReentrant updateUserList clearDustShare {
        UserInfo storage user = users[msg.sender];
        require (permanentWhitelist[msg.sender] || user.claimedAt < user.expireAt, "expired");
        require (user.amount <= (vipWhitelist[msg.sender] ? maxVipSupply : maxUserSupply), "exeeded user max supply");

        uint availableEarned = earned(msg.sender);
        require (availableEarned > 0, "!earned");

        uint _earned = _calculateExpiredEarning(msg.sender);
        uint left = availableEarned - _earned;
        uint share = _min((availableEarned * totalShare / balance()), user.share);

        user.share -= share;
        user.claimedAt = block.timestamp;
        totalShare -= share;
        profits -= _min(profits, availableEarned);
        
        uint _claimFee = _earned * claimFee / 100;
        uint _referralFee = _earned * referralFee / 100;
        address referral = referrals[msg.sender];
        
        if (_claimFee > 0) asset.safeTransfer(treasuryWallet, _claimFee);
        if (_referralFee > 0) {
            asset.safeTransfer(referral != address(0) ? referral : reserveWallet, _referralFee);
        }
        if (left > 0) asset.safeTransfer(reserveWallet, left);

        uint _payout = _earned - _claimFee - _referralFee;
        IPayoutAgent(payoutAgent).payout(msg.sender, _payout, _sellback);

        emit Claimed(msg.sender, _payout);
    }

    function compound() external whenNotPaused nonReentrant {
        UserInfo storage user = users[msg.sender];
        require (permanentWhitelist[msg.sender] || block.timestamp < user.expireAt, "expired");
        require (user.amount <= (vipWhitelist[msg.sender] ? maxVipSupply : maxUserSupply), "exeeded user max supply");

        uint _earned = earned(msg.sender);
        require (_earned > 0, "!earned");

        uint compounded = _earned * (100 - referralFee) / 100; // After 3% referral fee
        uint bal = balance();
        uint share1 = _earned * totalShare / bal;
        uint share2 = compounded * (totalShare - share1) / (bal - _earned);

        bool isVip = vipWhitelist[msg.sender];
        require (user.amount + compounded <= (isVip ? maxVipSupply : maxUserSupply), "exeeded user max supply");
        
        pendings.push(msg.sender);
        user.prevAmount = user.amount;
        user.prevShare = user.share;
        
        user.share -= (share1 - share2);
        user.amount += compounded;
        user.claimedAt = block.timestamp;
        totalShare -= (share1 - share2);
        totalSupply += compounded;
        profits -= _min(profits, _earned);

        address referral = referrals[msg.sender];
        // Taking 3% referral fee
        if (referralFee > 0) {
            asset.safeTransfer(referral != address(0) ? referral : reserveWallet, _earned * referralFee / 100);
        }

        _rebalance();

        emit Compounded(msg.sender, compounded);
    }

    function rebalance() external whenNotPaused nonReentrant {
        _rebalance();
    }
    
    function _rebalance() internal {
        uint invest = investable();
        if (invest == 0) return;
        asset.safeTransfer(strategy, invest);
        underlying += invest;
        IStrategy(strategy).deposit(invest);
    }

    function _calculateExpiredEarning(address _user) internal view returns (uint) {
        uint _claimedAt = users[_user].claimedAt;
        uint _expireAt = users[_user].expireAt;
        uint _earned = earned(_user);
        if (permanentWhitelist[_user] || _expireAt > block.timestamp) return _earned;
        if (_claimedAt >= _expireAt) return 0;
        return _earned * (_expireAt - _claimedAt) / (block.timestamp - _claimedAt);
    }

    function investable() public view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying - profits;
        uint keepBal = rebalanceRate * poolBal / 100 + profits;
        
        if (curBal <= keepBal) return 0;

        return curBal - keepBal;
    }

    function refillable() public view returns (uint) {
        uint curBal = available();
        uint poolBal = curBal + underlying - profits;
        uint keepBal = rebalanceRate * poolBal / 100 + profits;
        
        if (curBal >= keepBal) return 0;

        return keepBal - curBal;
    }

    function _min(uint x, uint y) internal pure returns (uint) {
        return x > y ? y : x;
    }

    function reportLoss(uint _loss) external onlyStrategy nonReentrant {
        require (_loss <= totalSupply / 2, "wrong lose report");

        dailyLoss[block.timestamp / 1 days * 1 days] += _loss;

        if (_loss <= profits) {
            profits -= _loss;
        } else {
            totalLoss += (_loss - profits);
            profits = 0;
        }
        underlying -= _loss;

        delete pendings;

        emit Lost(_loss);
    }

    function reportProfit(uint _profit) external onlyStrategy nonReentrant {
        require (asset.balanceOf(msg.sender) >= _profit, "!profit");
        require (asset.allowance(msg.sender, address(this)) >= _profit, "!allowance");

        dailyProfit[block.timestamp / 1 days * 1 days] += _profit;

        asset.safeTransferFrom(msg.sender, address(this), _profit);

        if (_profit > totalLoss) {
            profits += (_profit - totalLoss);
            totalProfits += (_profit - totalLoss);
            totalLoss = 0;
        } else {
            totalLoss -= _profit;
        }

        delete pendings;

        emit Payout(_profit);
    }

    function _isPending(address _user) internal view returns (bool) {
        for (uint i = 0; i < pendings.length; i++) {
            if (pendings[i] == _user) return true;
        }
        return false;
    }

    function close() external onlyStrategy whenPaused {
        require (underlying > 0, "!unerlying");
        asset.safeTransferFrom(msg.sender, address(this), underlying);
        underlying = 0;
    }

    function refill(uint _amount) external onlyStrategy nonReentrant {
        require (_amount <= underlying, "exceeded amount");
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        underlying -= _amount;

        emit Refilled(_amount);
    }

    function autoRefill() external onlyStrategy nonReentrant {
        uint amount = refillable();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        underlying -= amount;

        emit Refilled(amount);
    }

    function clearExpiredUsers(uint _count) external onlyOwner nonReentrant {
        uint count;
        for (uint i = 0; i < userList.length(); i++) {
            if (users[userList.at(i)].expireAt + expireDelta <= block.timestamp) ++count;
        }
        require (count > 0, "!expired users");
        
        address[] memory wallets = new address[](count);
        count = 0;
        for (uint i = 0; i < userList.length(); i++) {
            address user = userList.at(i);
            if (users[user].expireAt + expireDelta > block.timestamp) continue;
            
            uint bal = balanceOf(user);
            if (available() < bal) continue; // check over-withdrawal
            
            _withdrawAll(user, true);
            wallets[count] = user;
            ++count;

            if (count >= _count) break;
        }
        
        for (uint i = 0; i < count; i++) {
            userList.remove(wallets[i]);
        }
    }

    function updateFarmPeriod(uint _period, uint _vipPeriod) external onlyOwner {
        farmPeriod = _period;
        farmVipPeriod = _vipPeriod;
    }

    function updateExpireDelta(uint _delta) external onlyOwner {
        expireDelta = _delta;
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
            if (!_flag) permanentWhitelist[_wallets[i]] = false;
        }
    }

    function setReferrals(address[] calldata _wallets, address[] calldata _referrals) external onlyOwner {
        require (_wallets.length == _referrals.length, "!referral sets");
        for (uint i = 0; i < _wallets.length; i++) {
            require (_wallets[i] != _referrals[i], "!referral");
            require (invested[_referrals[i]], "!investor");
            referrals[_wallets[i]] = _referrals[i];
        }
    }

    function setPermanentWhitelist(address[] calldata _wallets, bool _flag) external onlyOwner {
        require (!isPublic, "!private mode");
        for (uint i = 0; i < _wallets.length; i++) {
            permanentWhitelist[_wallets[i]] = _flag;
        }
    }

    function setVipWhitelist(address[] calldata _wallets, bool _flag) external onlyOwner {
        require (!isPublic, "!private mode");
        for (uint i = 0; i < _wallets.length; i++) {
            address _user = _wallets[i];
            UserInfo storage user = users[_user];
            if (vipWhitelist[_user] == true && _flag == false && user.expireAt > block.timestamp) {
                user.expireAt = user.depositedAt + farmPeriod;
                // Update wrong last claimed time
                if (user.expireAt < user.claimedAt) user.claimedAt = user.expireAt;
            }
            if (vipWhitelist[_user] == false && _flag == true && user.expireAt > 0) {
                user.expireAt = user.depositedAt + farmVipPeriod;
                // Reset reward starting from the current time if it already expired
                if (user.expireAt < block.timestamp) user.claimedAt = block.timestamp;
            }
            vipWhitelist[_user] = _flag;
            if (_flag == true && !investWhitelist[_user]) investWhitelist[_user] = true;
        }
    }

    function setEliteWhitelist(address[] calldata _wallets, bool _flag) external onlyOwner {
        require (!isPublic, "!private mode");
        for (uint i = 0; i < _wallets.length; i++) {
            address _user = _wallets[i];
            eliteWhitelist[_user] = _flag;
            if (_flag == true && !investWhitelist[_user]) investWhitelist[_user] = true;
        }
    }

    function setAgent(address _agent, bool _flag) external onlyOwner {
        agents[_agent] = _flag;
    }

    function updatePayoutAgent(address _agent) external onlyOwner {
        require (_agent != address(0), "!agent");
        
        asset.approve(payoutAgent, 0);
        asset.approve(_agent, type(uint).max);
        payoutAgent = _agent;
    }

    function updateMaxSupply(uint _supply) external onlyOwner {
        maxSupply = _supply;
    }

    function updateUserMaxSupply(uint _supply, uint _vipSupply) external onlyOwner {
        maxUserSupply = _supply;
        maxVipSupply = _vipSupply;
    }

    function updateStrategy(address _strategy) external onlyOwner whenPaused {
        require (underlying == 0, "existing underlying amount");
        strategy = _strategy;
    }

    function updateTreasuryWallet(address _wallet) external onlyOwner {
        treasuryWallet = _wallet;
    }

    function updateReserveWallet(address _wallet) external onlyOwner {
        reserveWallet = _wallet;
    }

    function updateFees(uint _withdrawal, uint _claim, uint _referral) external onlyOwner {
        withdrawalFee = _withdrawal;
        claimFee = _claim;
        referralFee = _referral;
    }

    function withdrawInStuck() external onlyOwner whenPaused {
        require (totalShare == 0, "existing user fund");
        uint curBal = available();
        asset.safeTransfer(msg.sender, curBal);
    }

    function lockWithdrawal(bool _flag) external onlyOwner {
        lockedWithdrawal = _flag;
    }

    function emergencyWithdraw(uint _amount) external onlyOwner whenPaused {
        uint curBal = balanceOf(address(this));
        require (curBal >= _amount, "!fund");

        asset.safeTransfer(msg.sender, _amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function migrate(address _vault) external onlyOwner {
        IVault vault = IVault(_vault);

        uint count = vault.userCount();
        address[] memory _userList = vault.getUserList();
        
        for (uint i = 0; i < count; i++) {
            address _user = _userList[i];
            (
                uint amount,
                uint share,
                uint expireAt,
                uint depositedAt,
                uint claimedAt
            ) = vault.users(_user);
            users[_user] = UserInfo(
                amount,
                0,
                share,
                0,
                expireAt,
                depositedAt,
                claimedAt
            );
            referrals[_user] = vault.referrals(_user);
            invested[_user] = vault.invested(_user);
            investWhitelist[_user] = vault.investWhitelist(_user);
            permanentWhitelist[_user] = vault.permanentWhitelist(_user);
            vipWhitelist[_user] = vault.vipWhitelist(_user);
            eliteWhitelist[_user] = vault.eliteWhitelist(_user);

            userList.add(_user);
        }

        underlying = vault.underlying();
        totalSupply = vault.totalSupply();
        totalShare = vault.totalShare();
        profits = vault.profits();
        totalProfits = vault.totalProfits();
        totalLoss = vault.totalLoss();
    }
}