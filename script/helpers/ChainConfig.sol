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
    string constant WETH_VAULT_SALT = "my-unique-salt-v9-weth";
    string constant USDC_VAULT_SALT = "my-unique-salt-v9-usdc";

    function getChainConfig() internal view returns (Config memory) {
        string memory chainName = vm.envString("CHAIN_NAME");
        bytes32 key = keccak256(bytes(chainName));

        if (key == keccak256("sepolia")) return _sepolia();
        if (key == keccak256("base")) return _base();

        revert(string.concat("Unknown CHAIN_NAME: ", chainName));
    }

    function _sepolia() private pure returns (Config memory) {
        return Config({
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

    function _base() private pure returns (Config memory) {
        return Config({
            factory: 0x363a9d605ca45cBfF3b597350DeADb53cdC292c7,
            accountant: 0x1D78f23bF0B3249eC05d879bCc30A4e05F6fc86E,
            decoder: 0x61d29005A8c46a4a5F4Ae9ae7E2DD051C93bEf35,
            authority: 0x673BfafB4e2712215B422347c1571421B83E8A3d,
            panopticPool: 0x2B07ca6D403ce0A3B176BD7036BbFC57A4a0aD83,
            wethCollateralTracker: 0xA0769A548909e52472E56116584789004b51644c,
            usdcCollateralTracker: 0x407113cFaE84B225143f7666B6C849f5aAA60f5c,
            weth: 0x4200000000000000000000000000000000000006,
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            token0: address(0),
            token1: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            chainName: "base"
        });
    }
}
