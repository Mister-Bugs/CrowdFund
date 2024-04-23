// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

// 定义一个ERC20接口
interface IERC20 {
    function transfer(address, uint) external returns (bool);

    function transferFrom(
        address,
        address,
        uint
    ) external returns (bool);
}

// 众筹合约
contract CrowdFund {
    // 发起众筹事件
    event Launch(
        uint id,
        address indexed creator,
        uint goal,
        uint32 startAt,
        uint32 endAt
    );
    // 取消众筹事件
    event Cancel(uint id);
    // 购买事件
    event Pledge(uint indexed id, address indexed caller, uint amount);
    // 取消购买事件
    event Unpledge(uint indexed id, address indexed caller, uint amount);
    // 领取资金事件
    event Claim(uint id);
    // 退款事件
    event Refund(uint id, address indexed caller, uint amount);

    // 众筹活动结构
    struct Campaign {
        // 众筹发起者
        address creator;
        // 目标筹资金额
        uint goal;
        // 已筹资金额
        uint pledged;
        // 开始时间戳
        uint32 startAt;
        // 结束时间戳
        uint32 endAt;
        // 目标是否已达成并且发起者已领取资金
        bool claimed;
    }

    // ERC20代币合约
    IERC20 public immutable token;
    // 已创建的众筹活动总数，也用于生成新众筹活动的ID
    uint public count;
    // 众筹活动ID到众筹活动结构的映射
    mapping(uint => Campaign) public campaigns;
    // 众筹活动ID到支持者及其贡献金额的映射
    mapping(uint => mapping(address => uint)) public pledgedAmount;

    // 构造函数，传入ERC20代币合约地址
    constructor(address _token) {
        token = IERC20(_token);
    }

    // 发起众筹活动函数
    function launch(
        uint _goal,
        uint32 _startAt,
        uint32 _endAt
    ) external {
        // 要求开始时间晚于当前时间
        require(_startAt >= block.timestamp, "start at < now");
        // 要求结束时间晚于开始时间
        require(_endAt >= _startAt, "end at < start at");
        // 要求结束时间早于当前时间90天以内
        require(_endAt <= block.timestamp + 90 days, "end at > max duration");

        // 增加众筹活动计数器
        count += 1;
        // 创建新的众筹活动并存入映射中
        campaigns[count] = Campaign({
            creator: msg.sender,
            goal: _goal,
            pledged: 0,
            startAt: _startAt,
            endAt: _endAt,
            claimed: false
        });

        // 发出发起众筹事件
        emit Launch(count, msg.sender, _goal, _startAt, _endAt);
    }

    // 取消众筹活动函数
    function cancel(uint _id) external {
        // 获取众筹活动
        Campaign memory campaign = campaigns[_id];
        // 要求调用者是众筹发起者
        require(campaign.creator == msg.sender, "not creator");
        // 要求未到达众筹开始时间
        require(block.timestamp < campaign.startAt, "started");

        // 从映射中删除众筹活动
        delete campaigns[_id];
        // 发出取消众筹事件
        emit Cancel(_id);
    }

    // 购买众筹活动的支持函数
    function pledge(uint _id, uint _amount) external {
        // 获取众筹活动
        Campaign storage campaign = campaigns[_id];
        // 要求已到达众筹开始时间
        require(block.timestamp >= campaign.startAt, "not started");
        // 要求未到达众筹结束时间
        require(block.timestamp <= campaign.endAt, "ended");

        // 增加众筹活动的已筹资金额
        campaign.pledged += _amount;
        // 增加支持者的贡献金额
        pledgedAmount[_id][msg.sender] += _amount;
        // 转移代币到合约
        token.transferFrom(msg.sender, address(this), _amount);

        // 发出购买事件
        emit Pledge(_id, msg.sender, _amount);
    }

    // 取消购买众筹活动的支持函数
    function unpledge(uint _id, uint _amount) external {
        // 获取众筹活动
        Campaign storage campaign = campaigns[_id];
        // 要求未到达众筹结束时间
        require(block.timestamp <= campaign.endAt, "ended");

        // 减少众筹活动的已筹资金额
        campaign.pledged -= _amount;
        // 减少支持者的贡献金额
        pledgedAmount[_id][msg.sender] -= _amount;
        // 转移代币给支持者
        token.transfer(msg.sender, _amount);

        // 发出取消购买事件
        emit Unpledge(_id, msg.sender, _amount);
    }

    // 领取众筹活动资金函数
    function claim(uint _id) external {
        // 获取众筹活动
        Campaign storage campaign = campaigns[_id];
        // 要求调用者是众筹发起者
        require(campaign.creator == msg.sender, "not creator");
        // 要求已到达众筹结束时间
        require(block.timestamp > campaign.endAt, "not ended");
        // 要求已达到众筹目标
        require(campaign.pledged >= campaign.goal, "pledged < goal");
        // 要求未领取过资金
        require(!campaign.claimed, "claimed");

        // 标记众筹已领取资金
        campaign.claimed = true;
        // 转移代币给众筹发起者
        token.transfer(campaign.creator, campaign.pledged);

        // 发出领取资金事件
        emit Claim(_id);
    }

    // 退款函数
    function refund(uint _id) external {
        // 获取众筹活动
        Campaign memory campaign = campaigns[_id];
        // 要求已到达众筹结束时间
        require(block.timestamp > campaign.endAt, "not ended");
        // 要求未达到众筹目标
        require(campaign.pledged < campaign.goal, "pledged >= goal");

        // 获取支持者的贡献金额
        uint bal = pledgedAmount[_id][msg.sender];
        // 清空支持者的贡献金额
        pledgedAmount[_id][msg.sender] = 0;
        // 转移代币给支持者
        token.transfer(msg.sender, bal);

        // 发出退款事件
        emit Refund(_id, msg.sender, bal);
    }
}
