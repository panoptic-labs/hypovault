// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Base.sol";

contract ChainConfig is CommonBase {
    struct Config {
        address factory;
        address accountant;
        address decoder;
        address authority;
        address panopticPool;
        address wethCollateralTracker;
        address usdcCollateralTracker;
        address weth;
        address usdc;
        address token0;
        address token1;
        string chainName;
    }

    // Signers (same across all chains)
    address constant WETH_TURNKEY = 0x8FfA6DAB99f8afc64F61BeF83F0966eD6362f24F;
    address constant USDC_TURNKEY = 0x3c1c79d0cfc316Ba959194c89696a8382d7d283b;

    // Salts (same across all chains)
    string constant WETH_VAULT_SALT = "my-salt-v0-weth";
    string constant USDC_VAULT_SALT = "my-salt-v0-usdc";

    function getChainConfig() internal view returns (Config memory) {
        string memory chainName = vm.envString("CHAIN_NAME");
        bytes32 key = keccak256(bytes(chainName));

        if (key == keccak256("sepolia")) return _sepolia();
        if (key == keccak256("base")) return _base();
        if (key == keccak256("mainnet")) return _mainnet();

        revert(string.concat("Unknown CHAIN_NAME: ", chainName));
    }

    function _sepolia() private pure returns (Config memory) {
        return
            Config({
                factory: 0x363a9d605ca45cBfF3b597350DeADb53cdC292c7,
                accountant: 0x25BBef1DF262c24aa1AACD1F7eCeEcc1a7AD08ab,
                decoder: 0xb899BE50BAF25BBB3A3ca3403256B3c703E5AB5d,
                authority: 0x673BfafB4e2712215B422347c1571421B83E8A3d,
                panopticPool: 0x03AFf7Be6A5afB2bC6830BC54778AF674006850A,
                wethCollateralTracker: 0x45f93888565bA53650Af5ceF6279776B0e6B8A92,
                usdcCollateralTracker: 0x7A5D178492dbdABcbBc6201D1021BEE145d48604,
                weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
                usdc: 0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A,
                token0: address(0),
                token1: 0xFFFeD8254566B7F800f6D8CDb843ec75AE49B07A,
                chainName: "sepolia"
            });
    }

    function _mainnet() private pure returns (Config memory) {
        return
            Config({
                factory: 0x4FAe3e0B293Df7980eB9D55dF5463e40E502546d,
                accountant: 0xCCAA8adC2776786Fd0A14Fb1f22D6089E0637a49,
                decoder: 0x1c8620AC42c1F69eE493B953165FCd1864DEB439,
                authority: 0xBddfe76460A6124e24E157599D0dD60519490f56,
                // Panoptic pool: ETH/USDC 0.3% (tick spacing 60)
                panopticPool: 0x00000000b8Dc165CC8E838eaB940a873826cBcD6,
                wethCollateralTracker: 0x3F09A5d583df28bE3e1E6e796195b54413B1C68a,
                usdcCollateralTracker: 0xaF483Cf4758c8c396693Ec56151C6f33a8f42E0b,
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                token0: address(0),
                token1: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                chainName: "mainnet"
            });
    }

    function _base() private pure returns (Config memory) {
        return
            Config({
                factory: 0x9bE53b169a41030f1710A9B82e9eA6413f14D12E,
                accountant: 0x345cA3407942f9d175c9eA8B90e83A36F570f852,
                decoder: 0x4A290b3EC46cF320421Bb2aaee96d445de31CF0b,
                authority: 0x278D37CaBFFB4B72D2866E30fEFE08aef773E0B6,
                panopticPool: 0xB50e8bb68f5855DA742f4579274902a20454174a,
                wethCollateralTracker: 0x0d82b189c96EbB1f44A7207e6A9cfB1e490f2869,
                usdcCollateralTracker: 0x9ba1082Ab3cb9edEA988697A14BBe543A3dABEd2,
                weth: 0x4200000000000000000000000000000000000006,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                token0: address(0),
                token1: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                chainName: "base"
            });
    }
}
