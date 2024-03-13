//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

// Base Imports
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import { ISafetyLocks } from "../../interfaces/ISafetyLocks.sol";
import { IExecutionEnvironment } from "../../interfaces/IExecutionEnvironment.sol";

import { SafetyBits } from "../../libraries/SafetyBits.sol";

import { CallConfig } from "../../types/DAppApprovalTypes.sol";
import "../../types/UserCallTypes.sol";
import "../../types/SolverCallTypes.sol";
import "../../types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "../../dapp/DAppControl.sol";

// Uni V2 Imports
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";

// Misc
import { SwapMath } from "./SwapMath.sol";

// import "forge-std/Test.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract V2DAppControl is DAppControl {
    uint256 public constant CONTROL_GAS_USAGE = 250_000;

    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant GOVERNANCE_TOKEN = address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    address public constant WETH_X_GOVERNANCE_POOL = address(0xd3d2E2692501A5c9Ca623199D38826e513033a17);

    address public constant BURN_ADDRESS =
        address(uint160(uint256(keccak256(abi.encodePacked("GOVERNANCE TOKEN BURN ADDRESS")))));

    bytes4 public constant SWAP = bytes4(IUniswapV2Pair.swap.selector);

    bool public immutable govIsTok0;

    event GiftedGovernanceToken(address indexed user, address indexed token, uint256 amount);

    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequenced: false,
                dappNoncesSequenced: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
                delegateUser: false,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
                zeroSolvers: true,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: true,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false
            })
        )
    {
        govIsTok0 = (IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token0() == GOVERNANCE_TOKEN);
        if (govIsTok0) {
            require(IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token1() == WETH, "INVALID TOKEN PAIR");
        } else {
            require(IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token0() == WETH, "INVALID TOKEN PAIR");
        }
    }

    function _preOpsCall(UserOperation calldata userOp) internal override returns (bytes memory) {
        require(bytes4(userOp.data) == SWAP, "ERR-H10 InvalidFunction");

        (
            uint256 amount0Out,
            uint256 amount1Out,
            , // address recipient // Unused
                // bytes memory swapData // Unused
        ) = abi.decode(userOp.data[4:], (uint256, uint256, address, bytes));

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(userOp.dapp).getReserves();

        uint256 amount0In =
            amount1Out == 0 ? 0 : SwapMath.getAmountIn(amount1Out, uint256(token0Balance), uint256(token1Balance));
        uint256 amount1In =
            amount0Out == 0 ? 0 : SwapMath.getAmountIn(amount0Out, uint256(token1Balance), uint256(token0Balance));

        // This is a V2 swap, so optimistically transfer the tokens
        // NOTE: The user should have approved the ExecutionEnvironment for token transfers
        _transferUserERC20(
            amount0Out > amount1Out ? IUniswapV2Pair(userOp.dapp).token1() : IUniswapV2Pair(userOp.dapp).token0(),
            userOp.dapp,
            amount0In > amount1In ? amount0In : amount1In
        );

        bytes memory emptyData;
        return emptyData;
    }

    // This occurs after a Solver has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocateValueCall(address, uint256 bidAmount, bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        address user = _user();

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).getReserves();

        ERC20(WETH).transfer(WETH_X_GOVERNANCE_POOL, bidAmount);

        uint256 amount0Out;
        uint256 amount1Out;

        if (govIsTok0) {
            amount0Out = ((997_000 * bidAmount) * uint256(token0Balance))
                / ((uint256(token1Balance) * 1_000_000) + (997_000 * bidAmount));
        } else {
            amount1Out = ((997_000 * bidAmount) * uint256(token1Balance))
                / (((uint256(token0Balance) * 1_000_000) + (997_000 * bidAmount)));
        }

        bytes memory nullBytes;
        IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).swap(amount0Out, amount1Out, user, nullBytes);

        emit GiftedGovernanceToken(user, GOVERNANCE_TOKEN, govIsTok0 ? amount0Out : amount1Out);

        /*
        // ENABLE FOR FOUNDRY TESTING
        console.log("----====++++====----");
        console.log("DApp Control");
        console.log("Governance Tokens Burned:", govIsTok0 ? amount0Out : amount1Out);
        console.log("----====++++====----");
        */
    }

    ///////////////// GETTERS & HELPERS // //////////////////

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        // This is a helper function called by solvers
        // so that they can get the proper format for
        // submitting their bids to the hook.
        return WETH;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
