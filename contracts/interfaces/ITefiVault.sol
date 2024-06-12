//SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

interface ITefiVault {
    function deposit(uint) external;
    function withdraw(uint, bool) external;
    function withdrawAll(bool) external;
    function claim(bool) external;
    function compound() external;
    function claimable(address) external view returns (uint);
    function principalOf(address) external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function earned(address) external view returns (uint);
    function lostOf(address) external view returns (uint);
}

interface ITefiVaultForPulse is ITefiVault {
    // Pay rewards from bot earning via this method with reward amount.
    // NOTE: The bot wallet needs to approve reward amount before calling this method
    function payout(uint) external;
    // The bot is able to refill some fund for users to witdraw.
    // NOTE: The bot will need approval like `payout` method 
    // and able to get exact amount to be refilled using `refillable` method
    function refill(uint) external;
    // The bot can calls this method instead of `refill` method.
    // This method will charge the bot exact refillable amount automatically.
    function autoRefill() external;
    // The bot reports lost amount using this method.
    function reportLoss(uint) external;
    // The bot will be able to return back all user funds using this method when it closed.
    // At that time, the contract will charge the bot current underlying amount
    // NOTE: Don't send any amount to the contract address directly
    function close() external;
    // The bot get exact current amount to need to refilled for user withdrawals using this method.
    function refillable() external view returns (uint);
    // It shows the amount how much the contract deposited to the bot.
    // NOTE: The contract track and update this value each deposits or lost report
    function underlying() external view returns (uint);
}