pragma solidity 0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ASTToken.sol";

// Copied and modified from SUSHI code:
// https://github.com/sushiswap/sushiswap/blob/master/contracts/MasterChef.sol

// MoneyMaker is the maker of AST. He can make AST and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once AST is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MoneyMaker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ASTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accASTPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accASTPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. ASTs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that ASTs distribution occurs.
        uint256 accASTPerShare; // Accumulated ASTs per share, times 1e12. See below.
    }

    // The AST TOKEN!
    ASTToken public AST;
    // Dev address.
    address public devaddr;
    // Block number when bonus AST period ends.
    uint256 public bonusEndBlock;
    // AST tokens created per block.
    uint256 public ASTPerBlock;
    // Bonus muliplier for early AST makers.
    uint256 public constant BONUS_MULTIPLIER = 10;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when AST mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    //todo delete
    //event pendingAST1(uint256 indexed ASTReward, uint256 indexed accASTPerShare, uint256 lpSupply);
    //event pendingAST2(uint256 indexed rewardDebt, uint256 indexed reward);
    //event Deposit1(uint256 indexed rewardDebt);
    //event Withdraw1(uint256 indexed rewardDEbt);

    //event TestWithdraw(address indexed user, uint256 indexed pid, uint256 amount,
    //    uint256  poolShare, uint256  pending);

    constructor(
        ASTToken _AST,
        address _devaddr,
        uint256 _ASTPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public {
        AST = _AST;
        devaddr = _devaddr;
        ASTPerBlock = _ASTPerBlock;
        bonusEndBlock = _bonusEndBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accASTPerShare: 0
        }));
    }

    // Update the given pool's AST allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }


    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock)
            );
        }
    }

    // View function to see pending ASTs on frontend.
    function pendingAST(uint256 _pid, address _user) external returns (uint256) {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accASTPerShare = pool.accASTPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 ASTReward = multiplier.mul(ASTPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accASTPerShare = accASTPerShare.add(ASTReward.mul(1e12).div(lpSupply));
            //emit pendingAST1(ASTReward, accASTPerShare, lpSupply);
        }
            //emit pendingAST2(user.rewardDebt, user.amount.mul(accASTPerShare).div(1e12).sub(user.rewardDebt));
        return user.amount.mul(accASTPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function mint(uint256 amount) public onlyOwner{
       /* address msgSender = _msgSender();
        address _owner = owner();
        emit OwnershipTransferred(_owner, msgSender);*/
        AST.mint(devaddr, amount);
    }
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 ASTReward = multiplier.mul(ASTPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        AST.mint(devaddr, ASTReward.div(10)); // TODO 10% fee
        AST.mint(address(this), ASTReward);
        pool.accASTPerShare = pool.accASTPerShare.add(ASTReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MoneyMaker for AST allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accASTPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                //to msg.sender pending amount
                safeASTTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            //from, to , value
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accASTPerShare).div(1e12);
        //emit Deposit1(user.rewardDebt);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MoneyMaker.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        // pid => mapping(address => userInfo) //UserInfo {amount, rewardDebt};
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accASTPerShare).div(1e12).sub(user.rewardDebt);
        //emit Withdraw1(user.rewardDebt);
        //emit TestWithdraw(msg.sender, _pid, _amount, pool.accASTPerShare, pending);
        if(pending > 0) {
            //to msg.sender pending amount
            // 100 - 100 * 5 * 1/100 = 100 - 0.5
            safeASTTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            // to msg.sender _amount
            // 100 + 100 * 5 *1/1000 = 100 + 0.5
            // _amount.add(_amount.mul(per2.div(1e12))
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accASTPerShare).div(1e12);
        //emit Withdraw1(user.rewardDebt);
        emit Withdraw(msg.sender, _pid, _amount);
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

    // Safe AST transfer function, just in case if rounding error causes pool to not have enough ASTs.
    function safeASTTransfer(address _to, uint256 _amount) internal {
        uint256 ASTBal = AST.balanceOf(address(this));
        if (_amount > ASTBal) {
            AST.transfer(_to, ASTBal);
        } else {
            AST.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: what?");
        devaddr = _devaddr;
    }
}
