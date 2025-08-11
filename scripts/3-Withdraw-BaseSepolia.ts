#!/usr/bin/env npx ts-node

/**
 * Privacy Pool Withdrawal Script for Base Sepolia
 * 
 * This script handles ONLY withdrawal execution:
 * 1. Loads specified deposit for withdrawal
 * 2. Generates new nullifier and secret for change output
 * 3. Builds complete Merkle trees from all deposits and ASP state
 * 4. Generates ZK withdrawal proof
 * 5. Executes withdrawal via paymaster (gas-sponsored)
 * 6. Updates deposit status to "withdrawn"
 * 7. Saves new nullifier/secret as a change commitment
 * 
 * Usage: npx ts-node 3-Withdraw-BaseSepolia.ts <deposit_index> [withdrawal_amount_eth]
 * Examples: 
 *   npx ts-node 3-Withdraw-BaseSepolia.ts 0              # Withdraw deposit 0 (full amount)
 *   npx ts-node 3-Withdraw-BaseSepolia.ts 1 0.0005       # Withdraw 0.0005 ETH from deposit 1
 */

import { 
    createPublicClient, 
    http, 
    formatEther, 
    parseEther, 
    encodeAbiParameters,
    encodeFunctionData,
    Address,
    Hex,
    parseAbi,
    decodeEventLog
} from "viem";
import { baseSepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { entryPoint07Address } from "viem/account-abstraction";
import { LeanIMT } from "@zk-kit/lean-imt";
import { poseidon } from "maci-crypto/build/ts/hashing.js";
import { keccak256 } from "viem";
import { 
    createSmartAccountClient,
} from "permissionless";
import { toSimpleSmartAccount } from "permissionless/accounts";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from 'dotenv';
import { WithdrawalProofGenerator } from "../utils/WithdrawalProofGenerator";
dotenv.config();

// ============ CONFIGURATION ============
const CONFIG = {
    // Network Configuration
    RPC_URL: "https://sepolia.base.org",
    
    // Contract Addresses (Base Sepolia Deployed)
    CONTRACTS: {
        ENTRYPOINT: "0x67992c861b7559FBB6F5B6d55Cc383472D80e0A5",
        PRIVACY_POOL: "0xbBB978Ad37d847ffa1651900Ca75837212EBdf1f",
        PAYMASTER: "0x1D84295EA19D1EE44ECe18a098789494000aFc04",
        WITHDRAWAL_VERIFIER: "0x4A679253410272dd5232B3Ff7cF5dbB88f295319",
    },
    
    // Wallet Configuration
    PRIVATE_KEY: process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001",
    
    // Pimlico Configuration for Account Abstraction
    PIMLICO_API_KEY: process.env.PIMLICO_API_KEY || "your-pimlico-api-key",
    BUNDLER_URL: `https://api.pimlico.io/v2/84532/rpc?apikey=${process.env.PIMLICO_API_KEY}`,
    
    // Storage
    SECRETS_FILE: path.join(__dirname, "..", "privacy-pool-secrets.json"),
} as const;

// ============ CONTRACT ABIS ============
// Note: ENTRYPOINT_ABI not needed as we build the call data manually

const PRIVACY_POOL_ABI = parseAbi([
    // Get the unique scope identifier for this pool (used in ZK proofs)
    "function SCOPE() external view returns (uint256)",
]);

const SIMPLE_PRIVACY_POOL_PAYMASTER_ABI = parseAbi([
    "event PrivacyPoolWithdrawalSponsored(address userAccount, bytes32 userOpHash, uint256 actualWithdrawalCost, uint256 refunded)",
]);

// ============ TYPES ============
interface DepositRecord {
    timestamp: string;
    nullifier: string;
    secret: string;
    precommitment: string;
    commitment: string;
    label: string;
    transactionHash: string;
    blockNumber: string;
    depositIndex: number;
    amount: string;
    status: "deposited" | "asp_approved" | "withdrawn";
}

interface WithdrawalRecord {
    timestamp: string;
    sourceDepositIndex: number;
    withdrawalAmount: string;
    changeAmount: string;
    newNullifier: string;
    newSecret: string;
    newCommitment: string;
    transactionHash: string;
    blockNumber: string;
    userOpHash: string;
    recipient: string;
}

interface PrivacyPoolState {
    deposits: DepositRecord[];
    aspHistory: any[];
    withdrawals: WithdrawalRecord[];
    lastDepositIndex: number;
}

// ============ UTILITY FUNCTIONS ============
const SNARK_SCALAR_FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

function randomBigInt(): bigint {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
    return BigInt("0x" + hex) % SNARK_SCALAR_FIELD;
}

function hashToBigInt(data: string): bigint {
    const hash = keccak256(data as `0x${string}`);
    return BigInt(hash) % SNARK_SCALAR_FIELD;
}

// ============ STATE MANAGEMENT ============
function loadPrivacyPoolState(): PrivacyPoolState {
    try {
        if (fs.existsSync(CONFIG.SECRETS_FILE)) {
            const data = fs.readFileSync(CONFIG.SECRETS_FILE, 'utf8');
            return JSON.parse(data);
        }
    } catch (error) {
        console.warn("Could not load privacy pool state file");
    }
    
    return {
        deposits: [],
        aspHistory: [],
        withdrawals: [],
        lastDepositIndex: -1
    };
}

function savePrivacyPoolState(state: PrivacyPoolState) {
    const dir = path.dirname(CONFIG.SECRETS_FILE);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
    
    fs.writeFileSync(CONFIG.SECRETS_FILE, JSON.stringify(state, null, 2));
}

// ============ TREE BUILDING ============
function buildDepositTree(deposits: DepositRecord[]): { tree: LeanIMT; commitments: bigint[] } {
    console.log(`  Building deposit tree with ${deposits.length} deposits...`);
    
    const hash = (a: bigint, b: bigint) => poseidon([a, b]);
    const depositTree = new LeanIMT(hash);
    const commitments: bigint[] = [];
    
    // Add all known deposits to the tree in order
    deposits
        .sort((a, b) => a.depositIndex - b.depositIndex)
        .forEach((deposit) => {
            const commitment = BigInt(deposit.commitment);
            depositTree.insert(commitment);
            commitments.push(commitment);
            console.log(`    Added deposit ${deposit.depositIndex}: ${commitment.toString().slice(0, 20)}...`);
        });
    
    console.log(`  Deposit tree root: ${depositTree.root}`);
    return { tree: depositTree, commitments };
}

function buildASPTree(labels: bigint[]): LeanIMT {
    console.log(`  Building ASP tree with ${labels.length} labels...`);
    
    const hash = (a: bigint, b: bigint) => poseidon([a, b]);
    const aspTree = new LeanIMT(hash);
    
    labels.forEach((label, index) => {
        aspTree.insert(label);
        console.log(`    Added label ${index}: ${label.toString().slice(0, 20)}...`);
    });
    
    console.log(`  ASP tree root: ${aspTree.root}`);
    return aspTree;
}

// ============ WITHDRAWAL FUNCTIONS ============
async function executeWithdrawal(depositIndex: number, withdrawalAmount?: bigint) {
    console.log("\n" + "=" .repeat(70));
    console.log("💸 PRIVACY POOL WITHDRAWAL");
    console.log("=" .repeat(70));

    // Load current state
    const state = loadPrivacyPoolState();
    
    // Find the target deposit
    const targetDeposit = state.deposits.find(d => d.depositIndex === depositIndex);
    if (!targetDeposit) {
        throw new Error(`Deposit with index ${depositIndex} not found`);
    }
    
    if (targetDeposit.status !== "asp_approved") {
        throw new Error(`Deposit ${depositIndex} is not ASP approved. Current status: ${targetDeposit.status}`);
    }
    
    const depositAmount = BigInt(targetDeposit.amount);
    const defaultWithdrawal = depositAmount; // Full withdrawal by default
    const actualWithdrawal = withdrawalAmount || defaultWithdrawal;
    
    if (actualWithdrawal > depositAmount) {
        throw new Error(`Withdrawal amount ${formatEther(actualWithdrawal)} ETH exceeds deposit amount ${formatEther(depositAmount)} ETH`);
    }

    console.log(`📊 Withdrawal Details:`);
    console.log(`  Source deposit: ${depositIndex}`);
    console.log(`  Deposit amount: ${formatEther(depositAmount)} ETH`);
    console.log(`  Withdrawal amount: ${formatEther(actualWithdrawal)} ETH`);
    console.log(`  Change amount: ${formatEther(depositAmount - actualWithdrawal)} ETH`);

    // Set up clients
    const account = privateKeyToAccount(CONFIG.PRIVATE_KEY as `0x${string}`);
    const publicClient = createPublicClient({
        chain: baseSepolia,
        transport: http(CONFIG.RPC_URL),
    });

    // Note: walletClient not needed for Account Abstraction flow

    // Create smart account for withdrawal
    const simpleAccount = await toSimpleSmartAccount({
        owner: account as any,
        client: publicClient as any,
        entryPoint: { address: entryPoint07Address, version: "0.7" },
        index: randomBigInt(), // Random index for account creation
    });

    console.log(`\n👤 Withdrawal recipient: ${simpleAccount.address}`);

    // Build complete trees from all deposits and ASP history
    console.log(`\n🌳 Building Merkle trees...`);
    
    const { commitments } = buildDepositTree(state.deposits);
    
    // Get latest ASP state
    if (state.aspHistory.length === 0) {
        throw new Error("No ASP history found. Run 2-ApproveASP-BaseSepolia.ts first.");
    }
    
    const latestASP = state.aspHistory[state.aspHistory.length - 1];
    const aspLabels = latestASP.approvedLabels.map((l: string) => BigInt(l));
    console.log({aspLabels})
    buildASPTree(aspLabels); // Build ASP tree for validation
    
    console.log(`  Target deposit in trees: ${commitments.includes(BigInt(targetDeposit.commitment))}`);
    console.log(`  Target label in ASP: ${aspLabels.includes(BigInt(targetDeposit.label))}`);

    // Read privacy pool scope
    const scope = await publicClient.readContract({
        address: CONFIG.CONTRACTS.PRIVACY_POOL as `0x${string}`,
        abi: PRIVACY_POOL_ABI,
        functionName: "SCOPE",
    }) as bigint;

    console.log(`\n🔐 Generating withdrawal proof...`);
    console.log(`  Privacy pool scope: ${scope}`);

    // Generate new nullifier and secret for change output
    const newNullifier = randomBigInt();
    const newSecret = randomBigInt();
    
    console.log(`  New withdrawal nullifier: ${newNullifier}`);
    console.log(`  New withdrawal secret: ${newSecret}`);

    // Create withdrawal data structure for context
    const withdrawalData = [
        CONFIG.CONTRACTS.ENTRYPOINT,
        encodeAbiParameters(
            [
                { type: "address", name: "recipient" },
                { type: "address", name: "feeRecipient" },
                { type: "uint256", name: "relayFeeBPS" },
            ],
            [simpleAccount.address, CONFIG.CONTRACTS.PAYMASTER as `0x${string}`, BigInt(1000)]
        ),
    ] as const;

    // Calculate context hash
    const context = hashToBigInt(
        encodeAbiParameters(
            [
                { type: "tuple", components: [{ type: "address" }, { type: "bytes" }] }, 
                { type: "uint256" }
            ], 
            [withdrawalData, scope]
        )
    );

    console.log(`  Context hash: ${context}`);

    // Generate ZK proof (using mock for now)
    const prover = new WithdrawalProofGenerator();
    
    const withdrawalProof = await prover.generateWithdrawalProof({
        existingCommitmentHash: BigInt(targetDeposit.commitment),
        withdrawalValue: actualWithdrawal,
        context,
        label: BigInt(targetDeposit.label),
        existingValue: BigInt(targetDeposit.amount),
        existingNullifier: BigInt(targetDeposit.nullifier),
        existingSecret: BigInt(targetDeposit.secret),
        newNullifier,
        newSecret,
        stateTreeCommitments: commitments,
        aspTreeLabels: aspLabels,
    });

    console.log(`  ✅ ZK proof generated successfully!`);

    // Create smart account client with paymaster integration
    console.log(`\n🔗 Setting up Account Abstraction client...`);
    const smartAccountClient = createSmartAccountClient({
        client: publicClient as any,
        account: simpleAccount,
        bundlerTransport: http(CONFIG.BUNDLER_URL) as any,
        paymaster: {
            // Provide stub data for gas estimation - just hardcode high gas values
            async getPaymasterStubData() {
                return {
                    paymaster: CONFIG.CONTRACTS.PAYMASTER as Address,
                    paymasterData: "0x" as Hex, // Empty paymaster data
                    paymasterPostOpGasLimit: 35000n, // Above the 32,000 minimum
                };
            },
            // Provide real paymaster data for actual transaction
            async getPaymasterData() {
                return {
                    paymaster: CONFIG.CONTRACTS.PAYMASTER as Address,
                    paymasterData: "0x" as Hex, // Empty - paymaster validates via callData
                    paymasterPostOpGasLimit: 35000n, // Above the 32,000 minimum
                };
            },
        },
    });

    // Create relay call data for entrypoint
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

    // Execute withdrawal via UserOperation through paymaster
    console.log(`\n📤 Executing withdrawal via Account Abstraction...`);
    
    const preparedUserOperation = await smartAccountClient.prepareUserOperation({
        account: simpleAccount,
        calls: [
            {
                to: CONFIG.CONTRACTS.ENTRYPOINT as Address,
                data: relayCallData,
                value: 0n,
            },
        ],
    });

    // Get balances before transaction  
    const paymasterDepositBefore = await publicClient.readContract({
        address: entryPoint07Address, // Standard ERC-4337 EntryPoint address
        abi: parseAbi(["function balanceOf(address account) external view returns (uint256)"]),
        functionName: "balanceOf",
        args: [CONFIG.CONTRACTS.PAYMASTER as `0x${string}`],
    });
    const senderBalanceBefore = await publicClient.getBalance({ address: simpleAccount.address });
    
    console.log(`  Sender balance before: ${formatEther(senderBalanceBefore)} ETH`);
    console.log(`  Paymaster deposit before: ${formatEther(paymasterDepositBefore)} ETH`);

    // Sign and send UserOperation
    const signature = await simpleAccount.signUserOperation(preparedUserOperation);
    const userOpHash = await smartAccountClient.sendUserOperation({
        entryPointAddress: entryPoint07Address,
        ...preparedUserOperation,
        signature,
    });

    console.log(`  UserOperation hash: ${userOpHash}`);
    console.log(`  Waiting for UserOperation confirmation...`);

    // Wait for UserOperation receipt
    const receipt = await smartAccountClient.waitForUserOperationReceipt({ hash: userOpHash });
    
    if (!receipt.success) {
        throw new Error(`UserOperation failed: ${userOpHash}`);
    }

    console.log(`  ✅ Withdrawal executed successfully!`);
    console.log(`  UserOperation hash: ${userOpHash}`);
    console.log(`  Actual gas cost: ${receipt.actualGasCost}`);
    console.log(`  Gas used: ${receipt.actualGasUsed}`);

    // Get final balances and paymaster costs
    const paymasterDepositAfter = await publicClient.readContract({
        address: entryPoint07Address,
        abi: parseAbi(["function balanceOf(address account) external view returns (uint256)"]),
        functionName: "balanceOf",
        args: [CONFIG.CONTRACTS.PAYMASTER as `0x${string}`],
    });
    const senderBalanceAfter = await publicClient.getBalance({ address: simpleAccount.address });
    const paymasterNativeBalance = await publicClient.getBalance({
        address: CONFIG.CONTRACTS.PAYMASTER as `0x${string}`,
    });

    console.log(`  Paymaster deposit remaining: ${formatEther(paymasterDepositAfter)} ETH`);
    console.log(`  Gas paid by paymaster: ${formatEther(paymasterDepositBefore - paymasterDepositAfter)} ETH`);
    console.log(`  Sender balance after withdrawal: ${formatEther(senderBalanceAfter)} ETH`);
    console.log(`  Paymaster native balance: ${formatEther(paymasterNativeBalance)} ETH`);

    // Check for paymaster event
    receipt.receipt.logs.find((log) => {
        try {
            const decoded = decodeEventLog({
                abi: SIMPLE_PRIVACY_POOL_PAYMASTER_ABI,
                data: log.data,
                topics: log.topics,
            });
            if (decoded.eventName === "PrivacyPoolWithdrawalSponsored") {
                console.log(`  userAccount: ${decoded.args.userAccount}`);
                console.log(`  actualWithdrawalCost: ${formatEther(decoded.args.actualWithdrawalCost)} ETH`);
                console.log(`  refunded User: ${formatEther(decoded.args.refunded)} ETH`);
                return true;
            } else {
                console.log(`  Other event: ${decoded.eventName}`);
            }
            return false;
        } catch (e) {
            return false;
        }
    });

    // Update state
    targetDeposit.status = "withdrawn";
    
    const withdrawalRecord: WithdrawalRecord = {
        timestamp: new Date().toISOString(),
        sourceDepositIndex: depositIndex,
        withdrawalAmount: actualWithdrawal.toString(),
        changeAmount: (depositAmount - actualWithdrawal).toString(),
        newNullifier: newNullifier.toString(),
        newSecret: newSecret.toString(),
        newCommitment: poseidon([newNullifier, newSecret]).toString(),
        transactionHash: receipt.receipt.transactionHash || userOpHash,
        blockNumber: receipt.receipt.blockNumber?.toString() || "0",
        userOpHash: userOpHash,
        recipient: simpleAccount.address,
    };

    state.withdrawals.push(withdrawalRecord);
    
    // If there's change, add it as a new deposit
    if (depositAmount > actualWithdrawal) {
        const changeDeposit: DepositRecord = {
            timestamp: new Date().toISOString(),
            nullifier: newNullifier.toString(),
            secret: newSecret.toString(),
            precommitment: "N/A (change output)",
            commitment: withdrawalRecord.newCommitment,
            label: "N/A (change output)",
            transactionHash: receipt.receipt.transactionHash || userOpHash,
            blockNumber: receipt.receipt.blockNumber?.toString() || "0",
            depositIndex: state.lastDepositIndex + 1,
            amount: (depositAmount - actualWithdrawal).toString(),
            status: "deposited",
        };
        
        state.deposits.push(changeDeposit);
        state.lastDepositIndex = changeDeposit.depositIndex;
        
        console.log(`  🔄 Change output created as deposit ${changeDeposit.depositIndex}`);
        console.log(`  🔐 New nullifier: ${newNullifier}`);
        console.log(`  🔐 New secret: ${newSecret}`);
        console.log(`  📝 Note: Change deposit needs ASP approval before withdrawal`);
    }

    savePrivacyPoolState(state);

    console.log(`\n✅ WITHDRAWAL SUCCESSFUL!`);
    console.log(`  Withdrew: ${formatEther(actualWithdrawal)} ETH`);
    console.log(`  Change: ${formatEther(depositAmount - actualWithdrawal)} ETH`);
    console.log(`  Transaction: https://sepolia.basescan.org/tx/${receipt.receipt.transactionHash}`);

    return withdrawalRecord;
}

// ============ MAIN EXECUTION ============
async function main() {
    try {
        const args = process.argv.slice(2);
        
        if (args.length === 0) {
            console.error("Missing deposit index argument");
            console.log("\nUsage:");
            console.log("  npx ts-node 3-Withdraw-BaseSepolia.ts <deposit_index> [amount_eth]");
            console.log("\nExamples:");
            console.log("  npx ts-node 3-Withdraw-BaseSepolia.ts 0              # Full withdrawal");
            console.log("  npx ts-node 3-Withdraw-BaseSepolia.ts 1 0.0005       # Partial withdrawal");
            process.exit(1);
        }

        const depositIndex = parseInt(args[0]);
        if (isNaN(depositIndex)) {
            throw new Error("Invalid deposit index. Must be a number.");
        }

        let withdrawalAmount: bigint | undefined;
        if (args[1]) {
            withdrawalAmount = parseEther(args[1]);
        }

        await executeWithdrawal(depositIndex, withdrawalAmount);
        
        console.log("\n🎉 Withdrawal completed successfully!");
        process.exit(0);
    } catch (error) {
        console.error("\n❌ Withdrawal failed:", error);
        process.exit(1);
    }
}

// Run the script if executed directly
if (require.main === module) {
    main();
}

export { executeWithdrawal, loadPrivacyPoolState, CONFIG };
