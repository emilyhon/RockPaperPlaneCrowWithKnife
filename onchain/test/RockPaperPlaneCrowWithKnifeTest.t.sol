// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {RockPaperPlaneCrowWithKnife} from "../src/RockPaperPlaneCrowWithKnife.sol";

contract RockPaperPlaneCrowWithKnifeTest is Test {
    RockPaperPlaneCrowWithKnife public rppcwk;

    function setUp() public {
        rppcwk = new RockPaperPlaneCrowWithKnife();
    }

    function test_JoinGame() public {
        // todo
    }
}
