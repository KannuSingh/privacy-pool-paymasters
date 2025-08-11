#!/usr/bin/env npx ts-node

/**
 * Privacy Pool Deposit Creation Script for Base Sepolia
 * 
 * This script handles ONLY deposit creation:
 * 1. Generates nullifier and secret for new deposit
 * 2. Creates precommitment and submits to Privacy Pool
 * 3. Extracts label and commitment from deposit event
 * 4. Saves all critical data for future ASP approval and withdrawal
 * 
 * Usage: npx ts-node 1-CreateDeposit-BaseSepolia.ts [amount_in_eth]
 * Example: npx ts-node 1-CreateDeposit-BaseSepolia.ts 0.001
 */

import { createWalletClient, createPublicClient, http, formatEther, parseEther, parseAbi } from "viem";
import { baseSepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { decodeEventLog } from "viem";
import { poseidon } from "maci-crypto/build/ts/hashing.js";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from 'dotenv';
dotenv.config();

// ============ CONFIGURATION ============
const CONFIG = {
    // Network Configuration
    RPC_URL: "https://sepolia.base.org",
    CHAIN_ID: 84532,
    
    // Contract Addresses (Base Sepolia Deployed)
    CONTRACTS: {
        ENTRYPOINT: "0x67992c861b7559FBB6F5B6d55Cc383472D80e0A5",
        PRIVACY_POOL: "0xbBB978Ad37d847ffa1651900Ca75837212EBdf1f",
    },
    
    // Wallet Configuration
    PRIVATE_KEY: process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001",
    
    // Default deposit amount (0.001 ETH)
    DEFAULT_DEPOSIT_AMOUNT: parseEther("0.001"),
    
    // Storage
    SECRETS_FILE: path.join(__dirname, "..", "privacy-pool-secrets.json"),
} as const;

// ============ CONTRACT ABIS ============
const ENTRYPOINT_ABI = parseAbi([
    // Deposit precommitment to privacy pool and receive commitment hash
    "function deposit(uint256 _precommitment) external payable returns (uint256 _commitment)",
    // Event emitted when deposit is successful
    "event Deposited(address indexed _depositor, address indexed _pool, uint256 _commitment, uint256 _amount)",
]);

const PRIVACY_POOL_ABI = parseAbi([
    // Privacy Pool specific deposit event with all parameters
    "event Deposited(address indexed _depositor, uint256 _commitment, uint256 _label, uint256 _value, uint256 _precommitmentHash)",
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

interface PrivacyPoolState {
    deposits: DepositRecord[];
    aspHistory: any[];
    withdrawals: any[];
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

// ============ STATE MANAGEMENT ============
function loadPrivacyPoolState(): PrivacyPoolState {
    try {
        if (fs.existsSync(CONFIG.SECRETS_FILE)) {
            const data = fs.readFileSync(CONFIG.SECRETS_FILE, 'utf8');
            const parsed = JSON.parse(data);
            
            // Handle legacy format (array of deposits)
            if (Array.isArray(parsed)) {
                return {
                    deposits: parsed.map((item: any, index: number) => ({
                        ...item,
                        depositIndex: item.depositIndex ?? index,
                        amount: item.amount ?? CONFIG.DEFAULT_DEPOSIT_AMOUNT.toString(),
                        status: item.status ?? "deposited"
                    })),
                    aspHistory: [],
                    withdrawals: [],
                    lastDepositIndex: parsed.length - 1
                };
            }
            
            return parsed;
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

function saveDepositRecord(data: DepositRecord) {
    let state = loadPrivacyPoolState();
    
    state.deposits.push(data);
    state.lastDepositIndex = data.depositIndex;
    
    // Ensure directory exists
    const dir = path.dirname(CONFIG.SECRETS_FILE);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
    
    // Save to file
    fs.writeFileSync(CONFIG.SECRETS_FILE, JSON.stringify(state, null, 2));
    
    console.log(`  🔐 CRITICAL: Deposit ${data.depositIndex} saved to ${CONFIG.SECRETS_FILE}`);
    console.log(`  🔐 Nullifier: ${data.nullifier}`);
    console.log(`  🔐 Secret: ${data.secret}`);
    console.log(`  🔐 Total deposits tracked: ${state.deposits.length}`);
    console.log(`  🔐 BACKUP THESE VALUES - NEEDED FOR WITHDRAWAL!`);
}

// ============ DEPOSIT CREATION ============
async function createDeposit(depositAmount: bigint) {
    console.log("\n" + "=" .repeat(70));
    console.log("🏦 PRIVACY POOL DEPOSIT CREATION");
    console.log("=" .repeat(70));

    // Load existing state to determine next deposit index
    const state = loadPrivacyPoolState();
    const nextDepositIndex = state.lastDepositIndex + 1;
    
    console.log(`📊 Current State:`);
    console.log(`  Total existing deposits: ${state.deposits.length}`);
    console.log(`  Next deposit index: ${nextDepositIndex}`);
    console.log(`  Deposit amount: ${formatEther(depositAmount)} ETH`);
    console.log(`  Using RPC URL: ${CONFIG.RPC_URL}`);
    console.log(`  Using Chain ID: ${CONFIG.CHAIN_ID}`);
    console.log(` Private Key: ${CONFIG.PRIVATE_KEY.slice(0, 10)}... (DO NOT SHARE THIS!)`);
    // Set up clients
    const account = privateKeyToAccount(CONFIG.PRIVATE_KEY as `0x${string}`);
    const walletClient = createWalletClient({
        account,
        chain: baseSepolia,
        transport: http(CONFIG.RPC_URL),
    });

    const publicClient = createPublicClient({
        chain: baseSepolia,
        transport: http(CONFIG.RPC_URL),
    });

    console.log(`\n👤 Account: ${account.address}`);

    // Check balance
    const balance = await publicClient.getBalance({ address: account.address });
    console.log(`💰 Balance: ${formatEther(balance)} ETH`);
    
    if (balance < depositAmount) {
        throw new Error(`Insufficient balance. Need ${formatEther(depositAmount)} ETH, have ${formatEther(balance)} ETH`);
    }

    // Create commitment data structure following Privacy Pool protocol
    console.log(`\n🔒 Generating deposit commitment...`);
    
    const commitment = {
        value: depositAmount,
        nullifier: randomBigInt(), // Random nullifier for double-spend protection
        secret: randomBigInt(), // Random secret for commitment generation
        precommitment: BigInt(0), // Will be computed as hash(nullifier, secret)
        label: BigInt(0), // Will be extracted from deposit event
        commitmentHash: BigInt(0), // Will be extracted from deposit event
    };

    // Compute precommitment: Poseidon hash of nullifier and secret
    // This is what gets sent to the contract - the actual commitment is computed on-chain
    commitment.precommitment = poseidon([commitment.nullifier, commitment.secret]);
    
    console.log(`  Generated nullifier: ${commitment.nullifier}`);
    console.log(`  Generated secret: ${commitment.secret}`);
    console.log(`  Computed precommitment: ${commitment.precommitment}`);

    // Submit deposit transaction to the entrypoint
    console.log(`\n📤 Submitting deposit transaction...`);
    
    const depositTx = await walletClient.writeContract({
        address: CONFIG.CONTRACTS.ENTRYPOINT as `0x${string}`,
        abi: ENTRYPOINT_ABI,
        functionName: "deposit",
        args: [commitment.precommitment],
        value: commitment.value,
    });

    console.log(`  Transaction hash: ${depositTx}`);
    console.log(`  Waiting for confirmation...`);

    // Wait for transaction confirmation and get receipt
    const receipt = await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log(`  ✅ Deposit confirmed in block: ${receipt.blockNumber}`);

    // Extract label and commitment hash from Privacy Pool Deposited event
    console.log(`\n🔍 Extracting deposit data from event...`);
    
    const poolDepositedLog = receipt.logs.find((log: any) => {
        try {
            const decoded = decodeEventLog({
                abi: PRIVACY_POOL_ABI,
                data: log.data,
                topics: log.topics,
            });
            return decoded.eventName === "Deposited";
        } catch {
            return false;
        }
    });

    if (!poolDepositedLog) {
        throw new Error("Privacy Pool Deposited event not found in transaction receipt");
    }

    const poolEvent = decodeEventLog({
        abi: PRIVACY_POOL_ABI,
        data: poolDepositedLog.data,
        topics: poolDepositedLog.topics,
    }) as any;

    // Extract critical values from the event
    commitment.label = poolEvent.args._label as bigint;
    commitment.commitmentHash = poolEvent.args._commitment as bigint;
    const actualValue = poolEvent.args._value as bigint;

    console.log(`  Commitment Hash: ${commitment.commitmentHash}`);
    console.log(`  Label: ${commitment.label}`);
    console.log(`  Deposited Value: ${formatEther(actualValue)} ETH`);

    // Save all critical data to persistent storage
    const depositRecord: DepositRecord = {
        timestamp: new Date().toISOString(),
        nullifier: commitment.nullifier.toString(),
        secret: commitment.secret.toString(),
        precommitment: commitment.precommitment.toString(),
        commitment: commitment.commitmentHash.toString(),
        label: commitment.label.toString(),
        transactionHash: depositTx,
        blockNumber: receipt.blockNumber.toString(),
        depositIndex: nextDepositIndex,
        amount: actualValue.toString(),
        status: "deposited",
    };

    saveDepositRecord(depositRecord);

    console.log(`\n✅ DEPOSIT CREATION SUCCESSFUL!`);
    console.log(`  Deposit Index: ${nextDepositIndex}`);
    console.log(`  Amount: ${formatEther(actualValue)} ETH`);
    console.log(`  Status: deposited (ready for ASP approval)`);
    console.log(`  Transaction: https://sepolia.basescan.org/tx/${depositTx}`);
    
    console.log(`\n🔄 Next Steps:`);
    console.log(`  1. Run: npx ts-node scripts/2-ApproveASP-BaseSepolia.ts`);
    console.log(`  2. Then: npx ts-node scripts/3-Withdraw-BaseSepolia.ts ${nextDepositIndex}`);

    return depositRecord;
}

// ============ MAIN EXECUTION ============
async function main() {
    try {
        const args = process.argv.slice(2);
        const amountArg = args[0];
        
        let depositAmount = CONFIG.DEFAULT_DEPOSIT_AMOUNT;
        if (amountArg) {
            depositAmount = parseEther(amountArg);
            console.log(`Using custom deposit amount: ${formatEther(depositAmount)} ETH`);
        }

        await createDeposit(depositAmount);
        
        console.log("\n🎉 Deposit creation completed successfully!");
        process.exit(0);
    } catch (error) {
        console.error("\n❌ Deposit creation failed:", error);
        process.exit(1);
    }
}

// Run the script if executed directly
if (require.main === module) {
    main();
}

export { createDeposit, loadPrivacyPoolState, CONFIG };
