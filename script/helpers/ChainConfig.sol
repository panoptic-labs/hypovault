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
        // Timelock inputs (used by DeployTimelock.s.sol)
        address usdcVault;
        address usdcManager;
        address wethVault;
        address wethManager;
        address panopticMultisig; // PROPOSER + CANCELLER (+ EXECUTOR unless openExecution)
        uint256 timelockMinDelay;
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
                chainName: "sepolia",
                usdcVault: 0xdd7a8d6c6975488e801129bC84302d74e2361208,
                usdcManager: 0xFB5aa3e0b46F3859D90B14b52ffd287013b5Ec53,
                wethVault: 0xD58C4F9AEe5bBfcf28dC9a8d3D57b323fA6521b1,
                wethManager: 0x95eC124FAAB70D7aE147c3BE0336E01a828AE2d5,
                // Test Safe on sepolia, NOT the real Panoptic multisig
                panopticMultisig: 0x9C44C2B07380DA62a5ea572b886048410b0c44fd,
                timelockMinDelay: 2 days
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
                panopticPool: 0x000000007588B488d180899cDEa2080a886D2441,
                wethCollateralTracker: 0x6cd0186Fb4c32B6fD23279bBE0022506958216f9,
                usdcCollateralTracker: 0x6778d652A0BCe658C9a0E27D506eA20D179140e5,
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                token0: address(0),
                token1: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                chainName: "mainnet",
                usdcVault: 0x963Fe9c93bc353602656ee4051A75114bA74d6c5,
                usdcManager: 0xf42EED8F0d3326ad59fc1f5d4c4009B5F6B4D87c,
                wethVault: 0x779a2aa634A004b3a3f3b322083744869BBC6D66,
                wethManager: 0xcc80f113298DdF9D399323D5288aE5Eeaed20D44,
                panopticMultisig: 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1,
                timelockMinDelay: 2 days
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
                chainName: "base",
                usdcVault: 0xb452af299c565D04B05E601efF2840e000C922f1,
                usdcManager: 0xdd6E2406a044582463CFE9F0C774870eAf4A310B,
                wethVault: 0x41b7D0515d709A4Fd2CF27f9d141D0c2F8713D04,
                wethManager: 0x2a4923456c79E9ebD10F5Bf5305a5C742bBc1D7C,
                panopticMultisig: 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1,
                timelockMinDelay: 2 days
            });
    }
}
