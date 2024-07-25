// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge imports
import {Test, console} from "forge-std/Test.sol";

// Contract imports
import {PDTStaking} from "../src/contracts/PDTStaking.sol";
import {StakedPDT} from "../src/contracts/StakedPDT.sol";
import {WrappedStakedPDT} from "../src/contracts/WrappedStakedPDT.sol";
import {IStakedPDT} from "../src/interfaces/IStakedPDT.sol";

// Mock imports
import {PRIMEMock} from "../src/mocks/PRIMEMock.sol";
import {PROMPTMock} from "../src/mocks/PROMPTMock.sol";
import {PDTOFTMock} from "../src/mocks/PDTOFTMock.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract StakedPDTTestBase is Test, TestHelperOz5, IStakedPDT {
    // Mock endpoint of base/sepolia base chain
    uint32 bEid = 2;

    StakedPDT bStakedPDT;
    WrappedStakedPDT bWstPDT;
    PDTOFTMock bPDTOFT;
    PRIMEMock bPRIME;
    PROMPTMock bPROMPT;

    address bStakedPDTAddress;
    address bWstPDTAddress;
    address bPDTOFTAddress;
    address bPRIMEAddress;
    address bPROMPTAddress;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant EPOCH_MANAGER = keccak256("EPOCH_MANAGER");

    address owner;
    address epochManager = address(0x888);
    address staker1 = address(0x111);
    address staker2 = address(0x222);
    address staker3 = address(0x333);
    address staker4 = address(0x444);
    address staker5 = address(0x555);

    uint256 initialEpochLength = 4 weeks;
    uint256 initialFirstEpochStartIn = 1 days;

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        bPRIME = new PRIMEMock("PRIME Token", "PRIME");
        bPROMPT = new PROMPTMock("PROMPT Token", "PROMPT");

        bPDTOFT = PDTOFTMock(
            _deployOApp(
                type(PDTOFTMock).creationCode,
                abi.encode("ParagonsDAO Token", "PDT", address(endpoints[bEid]), address(this))
            )
        );

        bStakedPDT = new StakedPDT(
            "StakedPDT",
            "stPDT",
            initialEpochLength, // epochLength
            initialFirstEpochStartIn, // firstEpochStartIn
            address(bPDTOFT), // PDT address
            msg.sender // DEFAULT_ADMIN_ROLE
        );

        bWstPDT = new WrappedStakedPDT(address(bStakedPDT));

        bStakedPDTAddress = address(bStakedPDT);
        bWstPDTAddress = address(bWstPDT);
        bPDTOFTAddress = address(bPDTOFT);
        bPRIMEAddress = address(bPRIME);
        bPROMPTAddress = address(bPROMPT);

        owner = bStakedPDT.getRoleMember(DEFAULT_ADMIN_ROLE, 0);

        vm.startPrank(owner);
        bStakedPDT.grantRole(EPOCH_MANAGER, epochManager);
        vm.stopPrank();

        vm.startPrank(owner);
        bStakedPDT.registerNewRewardToken(address(bPRIME));
        bStakedPDT.updateWhitelistedContract(bWstPDTAddress, true);
        vm.stopPrank();
    }

    /**
     * Implement interface functions
     */

    function stake(address _to, uint256 _amount) external {}

    function unstake(address _to, uint256 _amount) external {}

    function claim(address _to) external {}

    /// Helper Functions ///

    function _creditPRIMERewardPool(uint256 _amount) internal {
        bPRIME.mint(address(bStakedPDT), _amount);
    }

    function _creditPROMPTRewardPool(uint256 _amount) internal {
        bPROMPT.mint(address(bStakedPDT), _amount);
    }

    function _moveToNextEpoch(uint256 _currentEpochId) internal {
        (, uint256 epochEndTime, ) = bStakedPDT.epoch(_currentEpochId);
        vm.warp(epochEndTime + 1 days);
        vm.startPrank(epochManager);
        bStakedPDT.distribute();
        vm.stopPrank();
    }
}
