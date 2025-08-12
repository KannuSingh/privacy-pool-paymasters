/**
 * Privacy Pool End-to-End Demonstration Script
 *
 * This script demonstrates a complete end-to-end flow for Privacy Pool with Account Abstraction:
 * 1. Deploy fresh contracts (Entrypoint, Privacy Pool, Paymaster)
 * 2. Create commitment and deposit funds to privacy pool
 * 3. Setup ASP (Approved Set of Participants) tree with approved labels
 * 4. Generate real ZK withdrawal proof using circuit infrastructure
 * 5. Test paymaster validation with UserOperation
 * 6. Execute withdrawal transaction via paymaster (not relayer)
 */

import {
    createPublicClient,
    createWalletClient,
    http,
    parseEther,
    formatEther,
    parseAbi,
    keccak256,
    encodeAbiParameters,
    encodeFunctionData,
    decodeEventLog,
    Hex,
    Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

// Account Abstraction imports for UserOperation and Smart Account setup
import { entryPoint07Address } from "viem/account-abstraction";
import { toSimpleSmartAccount } from "permissionless/accounts";
import { createSmartAccountClient } from "permissionless";
import { poseidon } from "maci-crypto/build/ts/hashing.js";
import { LeanIMT } from "@zk-kit/lean-imt";
import { WithdrawalProofGenerator } from "../utils/WithdrawalProofGenerator";
import { randomInt } from "crypto";
import { decode } from "punycode";

// ============ CONFIGURATION ============
/**
 * Configuration for the E2E test environment
 * Using Anvil local blockchain with Hardhat default account
 */
const CONFIG = {
    // Anvil local blockchain RPC endpoint
    RPC_URL: "http://localhost:8545",

    // Hardhat account #0 private key (publicly known, only for testing)
    PRIVATE_KEY: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",

    // Withdrawal recipient address (where funds should go)
    // This is the address that will receive the withdrawal funds and any refunds
    WITHDRAWAL_RECIPIENT_ADDRESS: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", // Hardhat account #0 address

    // Chain ID for local Anvil instance
    CHAIN_ID: 1,

    // Standard ERC-4337 EntryPoint contract address (same across all networks)
    ERC4337_ENTRYPOINT: "0x0000000071727De22E5E9d8BAf0edAc6f37da032",

    // Alto bundler URL from mock-aa-environment
    BUNDLER_URL: "http://localhost:4337",

    // Test amounts for deposit and withdrawal
    DEPOSIT_AMOUNT: parseEther("1"), // Deposit 1 ETH
    WITHDRAW_AMOUNT: parseEther("0.5"), // Withdraw 0.5 ETH (partial withdrawal)
} as const;

// ============ CONTRACT ABIS ============
/**
 * Contract ABIs for interacting with deployed Privacy Pool contracts
 * Only including the functions and events we need for this E2E test
 */

// Entrypoint contract ABI - handles deposits, withdrawals, and ASP root updates
const ENTRYPOINT_ABI = parseAbi([
    // Update ASP (Approved Set of Participants) root with new merkle root and IPFS CID
     "function updateRoot(uint256 _root, string memory _ipfsCID) external returns (uint256 _index)",

    // Relay withdrawal transaction with ZK proof - correct ProofLib.WithdrawProof structure
    "function relay((address,bytes) withdrawal, (uint256[2],uint256[2][2],uint256[2],uint256[8]) proofData, uint256 scope) external",

    // Deposit precommitment to privacy pool and receive commitment hash
    "function deposit(uint256 precommitment) external payable returns (uint256)",

    // Event emitted when deposit is successful
    "event Deposited(address indexed _depositor, address indexed _pool, uint256 _commitment, uint256 _amount)",
]);

// Privacy Pool contract ABI - for reading pool metadata and events
const PRIVACY_POOL_ABI = parseAbi([
    // Get the unique scope identifier for this pool (used in ZK proofs)
    "function SCOPE() external view returns (uint256)",

    // Get current merkle tree root for state verification
    "function currentRoot() external view returns (uint256)",

    // Event with detailed deposit information including label and precommitment
    "event Deposited(address indexed _depositor, uint256 _commitment, uint256 _label, uint256 _value, uint256 _precommitmentHash)",
]);
// Privacy Pool contract ABI - for reading pool metadata and events
const SIMPLE_PRIVACY_POOL_PAYMASTER_ABI = parseAbi([
    "event PrivacyPoolWithdrawalSponsored(address userAccount, bytes32 userOpHash, uint256 actualWithdrawalCost, uint256 refunded)",
]);

// ============ UTILITY FUNCTIONS ============
/**
 * Utility functions for cryptographic operations and data manipulation
 */

// SNARK scalar field modulus - all ZK proof values must be within this field
const SNARK_SCALAR_FIELD = BigInt("21888242871839275222246405745257275088548364400416034343698204186575808495617");

/**
 * Generate a random bigint value for nullifiers and secrets
 * @returns Random bigint within JavaScript's safe integer range
 */
function randomBigInt(): bigint {
    return BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));
}

/**
 * Convert hex string to bigint within SNARK scalar field
 * Used for context hashing in ZK proofs
 * @param data - Hex string to convert
 * @returns BigInt reduced by SNARK scalar field modulus
 */
function hashToBigInt(data: string): bigint {
    const hash = keccak256(data as `0x${string}`);
    return BigInt(hash) % SNARK_SCALAR_FIELD;
}

// ============ FRESH CONTRACT DEPLOYMENT ============
/**
 * Deploy fresh contracts for each test run to avoid state accumulation issues
 *
 * This function uses Forge script to deploy:
 * 1. Withdrawal and Commitment Verifiers (Groth16 proof verification)
 * 2. Privacy Pool Entrypoint (main protocol coordinator)
 * 3. Privacy Pool Simple (pool for ETH deposits/withdrawals)
 * 4. Privacy Pool Paymaster (Account Abstraction gas sponsorship)
 *
 * The deployment script also:
 * - Sets up proper access control (deployer as OWNER and POSTMAN)
 * - Registers the privacy pool with the entrypoint
 * - Funds the paymaster with ETH for gas sponsorship
 *
 * @param walletClient - Viem wallet client for transactions
 * @param publicClient - Viem public client for reading blockchain state
 * @returns Object containing deployed contract addresses
 */
async function deployContracts() {
    console.log("STEP 1: Deploy contracts");

    console.log("  Running forge script to deploy contracts...");

    // Execute the Forge deployment script
    const result = await new Promise<string>((resolve, reject) => {
        const { spawn } = require("child_process");
        const forge = spawn(
            "forge",
            [
                "script",
                "script/Deploy.s.sol:Deploy", // E2E deployment script
                "--rpc-url",
                CONFIG.RPC_URL, // Local Anvil RPC
                "--private-key",
                CONFIG.PRIVATE_KEY, // Deployer private key
                "--broadcast", // Actually send transactions
                "--legacy", // Use legacy transaction format
                "--skip-simulation", // Skip simulation, deploy directly
            ],
            { cwd: process.cwd() }
        );

        let output = "";

        // Capture stdout for address extraction
        forge.stdout.on("data", (data: Buffer) => {
            const text = data.toString();
            output += text;
            console.log(`    ${text.trim()}`);
        });

        // Log stderr for debugging
        forge.stderr.on("data", (data: Buffer) => {
            console.log(`    ${data.toString().trim()}`);
        });

        // Handle process completion
        forge.on("close", (code: number) => {
            if (code === 0) {
                resolve(output);
            } else {
                reject(new Error(`Forge script failed with code ${code}`));
            }
        });
    });

    // Extract deployed contract addresses from forge script output
    // The deployment script logs addresses in format: "CONTRACT_NAME: 0x..."
    const entrypointMatch = result.match(/ENTRYPOINT:\s+(0x[a-fA-F0-9]{40})/);
    const privacyPoolMatch = result.match(/PRIVACY_POOL:\s+(0x[a-fA-F0-9]{40})/);
    const paymasterMatch = result.match(/PAYMASTER:\s+(0x[a-fA-F0-9]{40})/);
    const withdrawalVerifierMatch = result.match(/WITHDRAWAL_VERIFIER:\s+(0x[a-fA-F0-9]{40})/);

    if (!entrypointMatch || !privacyPoolMatch || !paymasterMatch || !withdrawalVerifierMatch) {
        throw new Error("Failed to extract contract addresses from forge output");
    }

    const addresses = {
        ENTRYPOINT: entrypointMatch[1] as `0x${string}`,
        PRIVACY_POOL: privacyPoolMatch[1] as `0x${string}`,
        PAYMASTER: paymasterMatch[1] as `0x${string}`,
        WITHDRAWAL_VERIFIER: withdrawalVerifierMatch[1] as `0x${string}`,
    };

    return addresses;
}

// ============ MAIN E2E TEST FUNCTION ============
/**
 * Main demonstration function that shows the complete Privacy Pool flow
 * with Account Abstraction paymaster integration
 */
async function runPrivacyPoolDemo() {
    console.log("🚀 Privacy Pool E2E Demonstration\n");

    // STEP 0: Setup blockchain clients and account
    console.log("Setting up blockchain clients...");

    // Create account from private key
    const account = privateKeyToAccount(CONFIG.PRIVATE_KEY);

    // Create public client for reading blockchain state
    const publicClient = createPublicClient({
        transport: http(CONFIG.RPC_URL),
        chain: {
            id: CONFIG.CHAIN_ID,
            name: "Anvil",
            nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
            rpcUrls: { default: { http: [CONFIG.RPC_URL] } },
        },
    });

    // Create wallet client for sending transactions
    const walletClient = createWalletClient({
        account,
        transport: http(CONFIG.RPC_URL),
        chain: {
            id: CONFIG.CHAIN_ID,
            name: "Anvil",
            nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
            rpcUrls: { default: { http: [CONFIG.RPC_URL] } },
        },
    });

    console.log(`Account: ${account.address}`);
    console.log(`Balance: ${formatEther(await publicClient.getBalance({ address: account.address }))} ETH\n`);

    // STEP 1: Deploy PrivacyPool and Paymaster contracts
    const addresses = await deployContracts();

    // =================================================================
    // STEP 2: CREATE COMMITMENT AND DEPOSIT TO PRIVACY POOL
    // =================================================================
    console.log("STEP 2: Create commitment and deposit");

    // Create commitment data structure
    // Privacy pools use commitments to hide the link between deposits and withdrawals
    const commitment = {
        value: CONFIG.DEPOSIT_AMOUNT, // Amount being deposited (1 ETH)
        nullifier: randomBigInt(), // Random nullifier for double-spend protection
        secret: randomBigInt(), // Random secret for commitment generation
        precommitment: BigInt(0), // Will be computed as hash(nullifier, secret)
        label: BigInt(0), // Will be extracted from deposit event
        commitmentHash: BigInt(0), // Will be extracted from deposit event
    };

    // Compute precommitment: hash(nullifier, secret)
    // This is sent to the contract, actual commitment hash is computed on-chain
    commitment.precommitment = poseidon([commitment.nullifier, commitment.secret]);
    console.log(`  Precommitment: ${commitment.precommitment.toString().slice(0, 20)}...`);

    // Deposit to privacy pool via Entrypoint contract
    // The Entrypoint will forward this to the registered Privacy Pool
    const depositHash = await walletClient.writeContract({
        address: addresses.ENTRYPOINT,
        abi: ENTRYPOINT_ABI,
        functionName: "deposit",
        args: [commitment.precommitment],
        value: commitment.value,
    });

    // Wait for deposit transaction to be mined
    const depositReceipt = await publicClient.waitForTransactionReceipt({ hash: depositHash });
    console.log(`  Deposit successful: ${depositHash}`);

    // If we got commitment from Entrypoint event, we need to get label from Pool event
    const poolDepositedLog = depositReceipt.logs.find((log) => {
        try {
            const decoded = decodeEventLog({
                abi: PRIVACY_POOL_ABI,
                data: log.data,
                topics: log.topics,
            });
            commitment.label = decoded.args._label as bigint;
            commitment.value = decoded.args._value as bigint;
            commitment.commitmentHash = decoded.args._commitment as bigint;
            return decoded.eventName === "Deposited";
        } catch (e) {
            return false;
        }
    });

    if (!poolDepositedLog) {
        throw new Error(`Could not find Deposited event in Pool`);
    }

    const poolBalance = await publicClient.getBalance({ address: addresses.PRIVACY_POOL });
    console.log(`  Pool balance: ${formatEther(poolBalance)} ETH`);

    console.log("STEP 3: Setup ASP tree");

    const hash = (a: bigint, b: bigint) => poseidon([a, b]);
    const aspTree = new LeanIMT(hash);
    // ASP tree contains labels, not commitment hashes
    aspTree.insert(commitment.label);

    console.log(`  ASP root: ${aspTree.root.toString().slice(0, 20)}...`);
    console.log(`  ASP tree contains label: ${commitment.label.toString().slice(0, 20)}...`);

    // Update ASP root (IPFS CID must be 32-64 chars)(ASP provider updates root with depositor label)
    const timestamp = new Date().toISOString();
    const mockIPFSCID = `QmASP${Date.now()}TestingOnly1234567890abcdefg`; // Valid IPFS CID format
    const aspUpdateRootTxHash = await walletClient.writeContract({
        address: addresses.ENTRYPOINT,
        abi: ENTRYPOINT_ABI,
        functionName: "updateRoot",
        args: [aspTree.root, mockIPFSCID],
    });

    await publicClient.waitForTransactionReceipt({ hash: aspUpdateRootTxHash });
    console.log(`  ASP update root tx hash: ${aspUpdateRootTxHash}`);

    // STEP 4: Setup Smart Account
    console.log("STEP 4: Setup Smart Account with AA libraries");

    // Create smart account for the user (deterministic account for paymaster interaction)
    const smartAccount = await toSimpleSmartAccount({
        owner: account as any, // Use the same account as owner
        client: publicClient as any,
        entryPoint: { address: entryPoint07Address, version: "0.7" },
        // Using deterministic account (no random index) for consistent testing
    });

    console.log(`  Smart Account created: ${smartAccount.address}`);
    console.log(`  Withdrawal recipient: ${CONFIG.WITHDRAWAL_RECIPIENT_ADDRESS}`);
    
    console.log("STEP 5: Generate withdrawal proof");

    // Verify Entrypoint contract is deployed
    const entrypointCode = await publicClient.getCode({ address: addresses.ENTRYPOINT });
    console.log(`  Entrypoint contract deployed: ${entrypointCode ? 'Yes' : 'No'}`);
    if (!entrypointCode) {
        throw new Error(`Entrypoint contract not found at address ${addresses.ENTRYPOINT}`);
    }

    // Get pool scope
    const scope = (await publicClient.readContract({
        address: addresses.PRIVACY_POOL,
        abi: PRIVACY_POOL_ABI,
        functionName: "SCOPE",
    })) as bigint;
    console.log(`  Pool scope: ${scope}`);

    // Create IPrivacyPool.Withdrawal data

    const withdrawalData = [
        // processooor
        addresses.ENTRYPOINT,
        //IEntrypoint.RelayData
        encodeAbiParameters(
            [
                { type: "address", name: "recipient" },
                { type: "address", name: "feeRecipient" },
                { type: "uint256", name: "relayFeeBPS" },
            ],
            [CONFIG.WITHDRAWAL_RECIPIENT_ADDRESS, addresses.PAYMASTER, BigInt(1000)] // 1% fee
        ),
    ] as const;

    //   uint256 context = uint256(
    //     keccak256(abi.encode(withdrawal, _ethPool.SCOPE()))
    // ) % SNARK_SCALAR_FIELD;
    const context = hashToBigInt(
        encodeAbiParameters([{ type: "tuple", components: [{ type: "address" }, { type: "bytes" }] }, { type: "uint256" }], [withdrawalData, scope])
    );

    const prover = new WithdrawalProofGenerator();
    const newNullifier = randomBigInt();
    const newSecret = randomBigInt();
    const depositStateTree = [commitment.commitmentHash]; //[actualCommitmentHash];
    const aspStateTree = [commitment.label];

    const withdrawalProof = await prover.generateWithdrawalProof({
        existingCommitmentHash: commitment.commitmentHash,
        withdrawalValue: CONFIG.WITHDRAW_AMOUNT,
        context: context,
        label: commitment.label,
        existingValue: commitment.value,
        existingNullifier: commitment.nullifier,
        existingSecret: commitment.secret,
        newNullifier: newNullifier,
        newSecret: newSecret,
        stateTreeCommitments: depositStateTree,
        aspTreeLabels: aspStateTree,
    });

    console.log("  Bundler client created for UserOperation submission");
    
    // Create smart account client with paymaster integration
    const smartAccountClient = createSmartAccountClient({
        client: publicClient as any,
        account: smartAccount,
        bundlerTransport: http(CONFIG.BUNDLER_URL) as any,
        paymaster: {
            // Provide stub data for gas estimation - just hardcode high gas values
            async getPaymasterStubData() {
                return {
                    paymaster: addresses.PAYMASTER as Address,
                    paymasterData: "0x" as Hex, // Empty paymaster data
                    paymasterPostOpGasLimit: 35000n, // Above the 32,000 minimum
                };
            },
            // Provide real paymaster data for actual transaction
            async getPaymasterData() {
                return {
                    paymaster: addresses.PAYMASTER as Address,
                    paymasterData: "0x" as Hex, // Empty - paymaster validates via callData
                    paymasterPostOpGasLimit: 35000n, // Above the 32,000 minimum
                };
            },
        },
    });

    const relayCallData = encodeFunctionData({
        abi: [
            {
                type: "function",
                name: "relay",
                inputs: [
                    {
                        name: "_withdrawal",
                        type: "tuple",
                        internalType: "struct IPrivacyPool.Withdrawal",
                        components: [
                            {
                                name: "processooor",
                                type: "address",
                                internalType: "address",
                            },
                            {
                                name: "data",
                                type: "bytes",
                                internalType: "bytes",
                            },
                        ],
                    },
                    {
                        name: "_proof",
                        type: "tuple",
                        internalType: "struct ProofLib.WithdrawProof",
                        components: [
                            {
                                name: "pA",
                                type: "uint256[2]",
                                internalType: "uint256[2]",
                            },
                            {
                                name: "pB",
                                type: "uint256[2][2]",
                                internalType: "uint256[2][2]",
                            },
                            {
                                name: "pC",
                                type: "uint256[2]",
                                internalType: "uint256[2]",
                            },
                            {
                                name: "pubSignals",
                                type: "uint256[8]",
                                internalType: "uint256[8]",
                            },
                        ],
                    },
                    {
                        name: "_scope",
                        type: "uint256",
                        internalType: "uint256",
                    },
                ],
                outputs: [],
                stateMutability: "nonpayable",
            },
        ],
        functionName: "relay",
        args: [
            {
                processooor: withdrawalData[0],
                data: withdrawalData[1],
            },
            {
                pA: [BigInt(withdrawalProof.proof.pi_a[0]), BigInt(withdrawalProof.proof.pi_a[1])],
                pB: [
                    // Swap coordinates for pi_b - this is required for compatibility between snarkjs and Solidity verifier
                    [BigInt(withdrawalProof.proof.pi_b[0][1]), BigInt(withdrawalProof.proof.pi_b[0][0])],
                    [BigInt(withdrawalProof.proof.pi_b[1][1]), BigInt(withdrawalProof.proof.pi_b[1][0])],
                ],
                pC: [BigInt(withdrawalProof.proof.pi_c[0]), BigInt(withdrawalProof.proof.pi_c[1])],
                pubSignals: [
                    BigInt(withdrawalProof.publicSignals[0]),
                    BigInt(withdrawalProof.publicSignals[1]),
                    BigInt(withdrawalProof.publicSignals[2]),
                    BigInt(withdrawalProof.publicSignals[3]),
                    BigInt(withdrawalProof.publicSignals[4]),
                    BigInt(withdrawalProof.publicSignals[5]),
                    BigInt(withdrawalProof.publicSignals[6]),
                    BigInt(withdrawalProof.publicSignals[7]),
                ],
            },
            scope,
        ],
    });
    const preparedUserOperation = await smartAccountClient.prepareUserOperation({
        account: smartAccount,
        calls: [
            {
                to: addresses.ENTRYPOINT as Address,
                data: relayCallData,
                value: 0n,
            },
        ],
    });

    const paymasterDepositBeforeUserOp = await publicClient.readContract({
        address: CONFIG.ERC4337_ENTRYPOINT, // EntryPoint address
        abi: parseAbi(["function balanceOf(address account) external view returns (uint256)"]),
        functionName: "balanceOf",
        args: [addresses.PAYMASTER],
    });
    const recipientBalanceBefore = await publicClient.getBalance({ address: CONFIG.WITHDRAWAL_RECIPIENT_ADDRESS });
    console.log(`  Recipient balance: ${formatEther(recipientBalanceBefore)} ETH`);
    console.log(`  Paymaster deposit before UserOp: ${formatEther(paymasterDepositBeforeUserOp)} ETH`);
    // console.log(`  Prepared UserOperation:`, {preparedUserOperation});
    const signature = await smartAccount.signUserOperation(preparedUserOperation);
    const userOpHash = await smartAccountClient.sendUserOperation({
        entryPointAddress: entryPoint07Address,
        ...preparedUserOperation,
        signature,
    });

    const receipt = await smartAccountClient.waitForUserOperationReceipt({ hash: userOpHash });
    if (receipt.success) {
        console.log(`\nSTEP 5: Withdrawal completed successfully!`);
        console.log(`  UserOperation hash: ${userOpHash} actualGasCost: ${receipt.actualGasCost} gasUsed: ${receipt.actualGasUsed}`);

        const poolBalance = await publicClient.getBalance({ address: addresses.PRIVACY_POOL });
        const recipientBalanceAfter = await publicClient.getBalance({ address: CONFIG.WITHDRAWAL_RECIPIENT_ADDRESS });

        console.log(`  Pool balance after withdrawal: ${formatEther(poolBalance)} ETH`);
        console.log(`  Recipient balance after withdrawal: ${formatEther(recipientBalanceAfter)} ETH`);
        console.log(`  Recipient gained: ${formatEther(recipientBalanceAfter - recipientBalanceBefore)} ETH`);

        const paymasterDeposit = await publicClient.readContract({
            address: CONFIG.ERC4337_ENTRYPOINT,
            abi: parseAbi(["function balanceOf(address account) external view returns (uint256)"]),
            functionName: "balanceOf",
            args: [addresses.PAYMASTER],
        });

        receipt.receipt.logs.find((log) => {
            try {
                const decoded = decodeEventLog({
                    abi: SIMPLE_PRIVACY_POOL_PAYMASTER_ABI,
                    data: log.data,
                    topics: log.topics,
                });
                if (decoded.eventName === "PrivacyPoolWithdrawalSponsored") {
                    console.log("userAccount:", decoded.args.userAccount);
                    console.log(`actualWithdrawalCost:${formatEther(decoded.args.actualWithdrawalCost)} ETH `);
                    console.log(`refunded User:${formatEther(decoded.args.refunded)} ETH `);
                }else{
                console.log(decoded.eventName);

                }
            } catch (e) {
                return false;
            }
        });

        const paymasterNativeBalance = await publicClient.getBalance({
            address: addresses.PAYMASTER,
        });
        console.log(`  Paymaster deposit remaining: ${formatEther(paymasterDeposit)} ETH`);
        console.log(`  Gas paid by paymaster: ${formatEther(paymasterDepositBeforeUserOp - paymasterDeposit)} ETH`);
        // Recipient balance already logged above with the gained amount

        console.log(`  Paymaster native balance: ${formatEther(paymasterNativeBalance)} ETH`);
        console.log(`  Paymaster profit: ${formatEther(paymasterDeposit - paymasterDepositBeforeUserOp + paymasterNativeBalance)} ETH`);
    } else {
        throw new Error(`UserOperation failed: ${userOpHash}`);
    }
}

// ============ MAIN EXECUTION ============
/**
 * Execute the Privacy Pool demonstration when script is run directly
 */
async function main() {
    try {
        await runPrivacyPoolDemo();
        console.log("\n🎉 Privacy Pool demonstration completed successfully!");
        process.exit(0);
    } catch (error) {
        console.error("\n❌ Demonstration failed:", error);
        process.exit(1);
    }
}

// Run the demonstration if this script is executed directly
if (require.main === module) {
    main();
}
