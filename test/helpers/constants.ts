import { BigNumber, utils } from "ethers";

export const consts = {
  DUMMY_ADDRESS: "0xDEADbeEfEEeEEEeEEEeEEeeeeeEeEEeeeeEEEEeE",

  COMPOUND_COMPTROLLER_ADDRESS: "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b",
  AAVE_V2_LENDING_POOL_ADDRESS: "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
  AAVE_DUMMY_REFERRAL_CODE: 0,
  AAVE_RATE_DECIMALS: 27,

  ZERO_BYTES: utils.formatBytes32String(""),
  RANDOM_BYTES: utils.formatBytes32String("ZpTw6Y3Ft4ruk7pmwTJF"),
  ZERO_ADDRESS: "0x0000000000000000000000000000000000000000",
  RANDOM_ADDRESS: "0x0000000000000000000000000000000000000123",
  ETH_ADDRESS: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
  INF: BigNumber.from(2).pow(256).sub(1),
  DEFAULT_CHAIN_ID: 31337,
  ONE_HOUR: BigNumber.from(3600),
  ONE_DAY: BigNumber.from(86400),
  ONE_WEEK: BigNumber.from(86400 * 7),
  FIFTEEN_DAY: BigNumber.from(86400 * 15),
  ONE_MONTH: BigNumber.from(2592000),
  THREE_MONTH: BigNumber.from(2592000 * 3),
  FIVE_MONTH: BigNumber.from(2592000 * 5),
  SIX_MONTH: BigNumber.from(2592000 * 6),
  ONE_YEAR: BigNumber.from(31536000),

  HG: { gasLimit: 80000000 },
  LG: { gasLimit: 200000 },
};
