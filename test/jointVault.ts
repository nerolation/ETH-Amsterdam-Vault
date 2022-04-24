import { ethers, waffle } from "hardhat";
import { BigNumber, Wallet, Contract } from "ethers";
import { expect } from "./shared/expect";
import { metaFixture } from "./shared/fixtures";
import { toBn } from "evm-bn";
import {
  ERC20Mock,
  Factory,
  Periphery,
  TestMarginEngine,
  JointVaultStrategy,
  AaveFCM,
  MockAToken,
  MockAaveLendingPool,
} from "../typechain";
import {
  APY_UPPER_MULTIPLIER,
  APY_LOWER_MULTIPLIER,
  MIN_DELTA_LM,
  MIN_DELTA_IM,
  SIGMA_SQUARED,
  ALPHA,
  BETA,
  XI_UPPER,
  XI_LOWER,
  T_MAX,
  TICK_SPACING,
} from "./shared/utilities";
import { advanceTimeAndBlock, getCurrentTimestamp } from "./helpers/time";
import { consts } from "./helpers/constants";
const erc20ABI = require("../artifacts/contracts/test/ERC20Mock.sol/ERC20Mock.json");

const createFixtureLoader = waffle.createFixtureLoader;

describe("Periphery", async () => {
  let wallet: Wallet, other: Wallet;
  let token: ERC20Mock;
  let jvUSDC: ERC20Mock;
  let mockAToken: MockAToken;
  let marginEngineTest: TestMarginEngine;
  let periphery: Periphery;
  let factory: Factory;
  let jointVault: JointVaultStrategy;
  let fcmTest: AaveFCM;
  let aaveLendingPool: MockAaveLendingPool;

  let loadFixture: ReturnType<typeof createFixtureLoader>;

  before("create fixture loader", async () => {
    [wallet, other] = await (ethers as any).getSigners();
    loadFixture = createFixtureLoader([wallet, other]);
  });

  beforeEach("deploy fixture", async () => {
    ({
      token,
      marginEngineTest,
      factory,
      fcmTest,
      mockAToken,
      aaveLendingPool,
    } = await loadFixture(metaFixture));

    await token.mint(wallet.address, BigNumber.from(10).pow(27).mul(2));

    await token
      .connect(wallet)
      .approve(marginEngineTest.address, BigNumber.from(10).pow(27));

    await token.mint(other.address, BigNumber.from(10).pow(27).mul(2));

    await token
      .connect(other)
      .approve(marginEngineTest.address, BigNumber.from(10).pow(27));

    const margin_engine_params = {
      apyUpperMultiplierWad: APY_UPPER_MULTIPLIER,
      apyLowerMultiplierWad: APY_LOWER_MULTIPLIER,
      minDeltaLMWad: MIN_DELTA_LM,
      minDeltaIMWad: MIN_DELTA_IM,
      sigmaSquaredWad: SIGMA_SQUARED,
      alphaWad: ALPHA,
      betaWad: BETA,
      xiUpperWad: XI_UPPER,
      xiLowerWad: XI_LOWER,
      tMaxWad: T_MAX,

      devMulLeftUnwindLMWad: toBn("0.5"),
      devMulRightUnwindLMWad: toBn("0.5"),
      devMulLeftUnwindIMWad: toBn("0.8"),
      devMulRightUnwindIMWad: toBn("0.8"),

      fixedRateDeviationMinLeftUnwindLMWad: toBn("0.1"),
      fixedRateDeviationMinRightUnwindLMWad: toBn("0.1"),

      fixedRateDeviationMinLeftUnwindIMWad: toBn("0.3"),
      fixedRateDeviationMinRightUnwindIMWad: toBn("0.3"),

      gammaWad: toBn("1.0"),
      minMarginToIncentiviseLiquidators: 0,
    };

    await marginEngineTest.setMarginCalculatorParameters(margin_engine_params);

    // deploy the periphery
    const peripheryFactory = await ethers.getContractFactory("Periphery");

    periphery = (await peripheryFactory.deploy()) as Periphery;

    // set the periphery in the factory
    await expect(factory.setPeriphery(periphery.address))
      .to.emit(factory, "PeripheryUpdate")
      .withArgs(periphery.address);

    // approve the periphery to spend tokens on wallet's behalf

    await token
      .connect(wallet)
      .approve(periphery.address, BigNumber.from(10).pow(27));

    await token
      .connect(other)
      .approve(periphery.address, BigNumber.from(10).pow(27));

    // Deploy JointVaultStrategy contract

    await token.mint(other.address, BigNumber.from(10).pow(27));
    await token
      .connect(other)
      .approve(marginEngineTest.address, BigNumber.from(10).pow(27));

    // mint underlyings to the mock aToken
    await token.mint(mockAToken.address, BigNumber.from(10).pow(27));
    const currentReserveNormalisedIncome =
      await aaveLendingPool.getReserveNormalizedIncome(token.address);

    const jointVaultFactory = await ethers.getContractFactory(
      "JointVaultStrategy"
    );

    const currentTimestamp = await getCurrentTimestamp();

    jointVault = (await jointVaultFactory.deploy(
      mockAToken.address,
      token.address,
      factory.address,
      fcmTest.address,
      marginEngineTest.address,
      aaveLendingPool.address,
      // '0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe', // for kovan fork
      {
        start: currentTimestamp,
        end: currentTimestamp + 86400, // one day later
      }
    )) as JointVaultStrategy;

    await jointVault.deployed();

    const jvUSDCAddress = await jointVault.JVUSDC();
    jvUSDC = new Contract(jvUSDCAddress, erc20ABI.abi, wallet) as ERC20Mock;

    // mint aTokens
    await mockAToken.mint(
      jointVault.address,
      toBn("100"),
      currentReserveNormalisedIncome
    );
  });

  describe.only("JointVaultStrategy Tests", async () => {
    describe("Execute tests", () => {
      it("executes a round", async () => {
        // advance time by two days
        await advanceTimeAndBlock(
          BigNumber.from(86400).mul(BigNumber.from(2)),
          4
        );

        await periphery.mintOrBurn({
          marginEngine: marginEngineTest.address,
          tickLower: -TICK_SPACING,
          tickUpper: TICK_SPACING,
          notional: toBn("100"),
          isMint: true,
          marginDelta: toBn("100000"),
        });

        await jointVault.execute();
      });

      it("cannot execute a round when collection window has not ended", async () => {
        await periphery.mintOrBurn({
          marginEngine: marginEngineTest.address,
          tickLower: -TICK_SPACING,
          tickUpper: TICK_SPACING,
          notional: toBn("100"),
          isMint: true,
          marginDelta: toBn("100000"),
        });

        await expect(jointVault.execute()).to.be.revertedWith(
          "Collection round has not finished"
        );
      });
    });

    describe("Settle tests", () => {
      let balanceBeforeExecutionAUSDC: BigNumber;
      let balanceBeforeExecutionUSDC: BigNumber;

      beforeEach(async () => {
        await token.increaseAllowance(jointVault.address, toBn("100"));
        await jointVault.deposit(toBn("100"));

        // advance time by two days
        await advanceTimeAndBlock(
          BigNumber.from(86400).mul(BigNumber.from(2)),
          4
        );

        await periphery.mintOrBurn({
          marginEngine: marginEngineTest.address,
          tickLower: -TICK_SPACING,
          tickUpper: TICK_SPACING,
          notional: toBn("100"),
          isMint: true,
          marginDelta: toBn("100000"),
        });

        balanceBeforeExecutionAUSDC = await mockAToken.balanceOf(
          jointVault.address
        );
        balanceBeforeExecutionUSDC = await token.balanceOf(jointVault.address);

        await jointVault.execute();
      });

      it("settles after maturity", async () => {
        const balanceAfterExecutionAUSDC = await mockAToken.balanceOf(
          jointVault.address
        );

        expect(balanceAfterExecutionAUSDC).is.lt(balanceBeforeExecutionAUSDC);

        // 5 days minimum need to pass until maturity as configured by test suite
        // await advanceTimeAndBlock(consts.ONE_DAY.mul(BigNumber.from(5)), 4);

        // Advance by one year to generate a good amount of yield
        await advanceTimeAndBlock(consts.ONE_YEAR, 4);

        await jointVault.settle();

        const balanceAfterSettlementAUSDC = await mockAToken.balanceOf(
          jointVault.address
        );
        const balanceAfterSettlementUSDC = await token.balanceOf(
          jointVault.address
        );

        expect(balanceAfterSettlementAUSDC).to.equal(
          balanceBeforeExecutionAUSDC
        );
        expect(
          balanceAfterSettlementUSDC.gt(balanceBeforeExecutionUSDC)
        ).to.equal(true);
      });

      it("cannot settle before termEnd", async () => {
        const balanceAfterExecutionAUSDC = await mockAToken.balanceOf(
          jointVault.address
        );

        expect(balanceAfterExecutionAUSDC).is.lt(balanceBeforeExecutionAUSDC);

        // 5 days minimum need to pass until maturity as configured by test suite
        await advanceTimeAndBlock(consts.ONE_DAY.mul(BigNumber.from(4)), 4);

        await expect(jointVault.settle()).to.be.revertedWith(
          "Not past term end"
        );
      });
    });

    describe("Deposit tests", () => {
      it("can execute a deposit when in collection window", async () => {
        await token.increaseAllowance(jointVault.address, toBn("1"));

        await expect(jointVault.deposit(toBn("1"))).to.not.be.reverted;
      });

      it("cannot execute a deposit when not in collection window", async () => {
        await token.increaseAllowance(jointVault.address, toBn("1"));

        // advance time by two days
        await advanceTimeAndBlock(
          BigNumber.from(86400).mul(BigNumber.from(2)),
          4
        );

        await expect(jointVault.deposit(toBn("1"))).to.be.revertedWith(
          "Collection window not open"
        );
      });
    });

    describe("Withdraw tests", () => {
      beforeEach(async () => {
        await token.increaseAllowance(jointVault.address, toBn("1", 6));

        await jointVault.deposit(toBn("1", 6));
      });

      it("can execute a withdraw when in collection window", async () => {
        await jvUSDC.increaseAllowance(jointVault.address, toBn("1", 18));

        // await jointVault.withdraw(toBn("1", 6));
        await expect(jointVault.withdraw(toBn("1", 6))).to.not.be.reverted;
      });

      it("cannot execute a withdraw when not in collection window", async () => {
        // advance time by two days
        await advanceTimeAndBlock(
          BigNumber.from(86400).mul(BigNumber.from(2)),
          4
        );

        await expect(jointVault.withdraw(toBn("1", 6))).to.be.revertedWith(
          "Collection window not open"
        );
      });
    });

    describe("Conversion factor tests", () => {
      beforeEach(async () => {
        await mockAToken.cheatBurn(jointVault.address, toBn("100"));
      });

      it("calculates conversion factor to be 0 when no jvUSDC minted", async () => {
        await expect(jointVault.conversionFactor()).to.be.revertedWith(
          "JVUSDC totalSupply is zero"
        );
      });

      it("calculates conversion factor to be 100 when jvUSDC is equal to amount of aUSDC", async () => {
        await token.increaseAllowance(jointVault.address, toBn("100"));
        await jointVault.deposit(toBn("100"));

        expect(await jointVault.conversionFactor()).to.equal(
          BigNumber.from(100)
        );
      });
    });

    describe("End to end scenario", () => {
      it("deposits, executes, settles, and withdraws", async () => {
        // deposit
        await token.increaseAllowance(jointVault.address, toBn("1000"));

        await mockAToken.cheatBurn(jointVault.address, toBn("100"));

        console.log(
          "balanceOf jointVault AUSDC before deposit",
          (await mockAToken.balanceOf(jointVault.address)).toString()
        );
        console.log(
          "balanceOf jointVault USDC before deposit",
          (await token.balanceOf(jointVault.address)).toString()
        );

        await jointVault.deposit(toBn("1000", 6));

        // advance time by two days and four blocks
        await advanceTimeAndBlock(
          BigNumber.from(86400).mul(BigNumber.from(2)),
          4
        );

        // provide liquidity into pool
        // await periphery.mintOrBurn({
        //   marginEngine: marginEngineTest.address,
        //   tickLower: -TICK_SPACING,
        //   tickUpper: TICK_SPACING,
        //   notional: toBn("100000000"),
        //   isMint: true,
        //   marginDelta: toBn("100000000"),
        // });

        await periphery.mintOrBurn({
          marginEngine: marginEngineTest.address,
          tickLower: -TICK_SPACING,
          tickUpper: TICK_SPACING,
          notional: toBn("10"),
          isMint: true,
          marginDelta: toBn("10000"),
        });

        console.log(
          "balanceOf jointVault AUSDC before execution",
          (await mockAToken.balanceOf(jointVault.address)).toString()
        );
        console.log(
          "balanceOf jointVault USDC before execution",
          (await token.balanceOf(jointVault.address)).toString()
        );

        // execute strategy
        await jointVault.execute();

        console.log(
          "balanceOf jointVault AUSDC before settlement",
          (await mockAToken.balanceOf(jointVault.address)).toString()
        );
        console.log(
          "balanceOf jointVault USDC before settlement",
          (await token.balanceOf(jointVault.address)).toString()
        );

        // fast forward one year with four blocks
        // await advanceTimeAndBlock(consts.ONE_YEAR.div(10), 4);
        await advanceTimeAndBlock(consts.ONE_DAY.mul(5), 4);

        // settle
        await jointVault.settle();

        const AUSDCBalance = await mockAToken.balanceOf(jointVault.address);
        const USDCBalance = await token.balanceOf(jointVault.address);

        console.log("balanceOf jointVault AUSDC", AUSDCBalance.toString());
        console.log("balanceOf jointVault USDC", USDCBalance.toString());

        const conversionFactor = await jointVault.conversionFactor();

        const AUSDCToWithdraw = conversionFactor.mul(1000);
        console.log("aUSDCToWithdraw", AUSDCToWithdraw.toString());
        console.log(
          "aUSDC wallet balance before withdraw",
          mockAToken.balanceOf(wallet.address).toString()
        );

        const JVUSDCBalance = await jvUSDC.balanceOf(wallet.address);

        console.log("JVUSDCBalance before withdraw", JVUSDCBalance.toString());

        await jvUSDC.increaseAllowance(jointVault.address, JVUSDCBalance);

        await jointVault.withdraw(AUSDCToWithdraw);

        console.log(
          "JVUSDCBalance after withdraw",
          (await jvUSDC.balanceOf(wallet.address)).toString()
        );
        console.log(
          "AUSDC wallet balance after withdraw",
          (await mockAToken.balanceOf(wallet.address)).toString()
        );
      });
    });
  });
});
