#!/usr/bin/env npx ts-node

/**
 * Privacy Pool ASP (Approved Set of Participants) Update Script for Base Sepolia
 * 
 * This script handles ONLY ASP root updates:
 * 1. Loads all deposited commitments that need ASP approval
 * 2. Builds complete ASP Merkle tree with approved participant labels
 * 3. Updates on-chain ASP root to make deposits eligible for withdrawal
 * 4. Marks deposits as "asp_approved" status
 * 
 * Usage: npx ts-node 2-ApproveASP-BaseSepolia.ts [deposit_indices...]
 * Examples: 
 *   npx ts-node 2-ApproveASP-BaseSepolia.ts           # Approve all pending deposits
 *   npx ts-node 2-ApproveASP-BaseSepolia.ts 0 1 2     # Approve specific deposits
 */

import { createWalletClient, createPublicClient, http, encodeAbiParameters, parseAbi } from "viem";
import { baseSepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { LeanIMT } from "@zk-kit/lean-imt";
import { poseidon } from "maci-crypto/build/ts/hashing.js";
import * as fs from "fs";
import * as path from "path";
import * as dotenv from 'dotenv';
dotenv.config();

// ============ CONFIGURATION ============
const CONFIG = {
    // Network Configuration
    RPC_URL: "https://sepolia.base.org",
    
    // Contract Addresses (Base Sepolia Deployed)
    CONTRACTS: {
        ENTRYPOINT: "0x67992c861b7559FBB6F5B6d55Cc383472D80e0A5",
    },
    
    // Wallet Configuration
    PRIVATE_KEY: process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001",
    
    // Storage
    SECRETS_FILE: path.join(__dirname, "..", "privacy-pool-secrets.json"),
} as const;

// ============ CONTRACT ABIS ============
const ENTRYPOINT_ABI = parseAbi([
    // Update ASP (Approved Set of Participants) root with new merkle root and IPFS CID  
    "function updateRoot(uint256 _root, string memory _ipfsCID) external returns (uint256 _index)",
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

interface ASPRecord {
    timestamp: string;
    root: string;
    ipfsCid: string;
    approvedLabels: string[];
    approvedDepositIndices: number[];
    transactionHash: string;
    blockNumber: string;
}

interface PrivacyPoolState {
    deposits: DepositRecord[];
    aspHistory: ASPRecord[];
    withdrawals: any[];
    lastDepositIndex: number;
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
    // Ensure directory exists
    const dir = path.dirname(CONFIG.SECRETS_FILE);
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
    }
    
    fs.writeFileSync(CONFIG.SECRETS_FILE, JSON.stringify(state, null, 2));
}

// ============ ASP TREE MANAGEMENT ============
function buildASPTree(labels: bigint[]): LeanIMT {
    console.log(`  Building ASP tree with ${labels.length} labels...`);
    
    const hash = (a: bigint, b: bigint) => poseidon([a, b]);
    const aspTree = new LeanIMT(hash);
    
    // Add all labels to the ASP tree
    labels.forEach((label, index) => {
        aspTree.insert(label);
        console.log(`    Added label ${index}: ${label}`);
    });
    
    console.log(`  ASP tree root: ${aspTree.root}`);
    return aspTree;
}

// ============ ASP APPROVAL FUNCTIONS ============
async function approveASP(depositIndices?: number[]) {
    console.log("\n" + "=" .repeat(70));
    console.log("🌳 PRIVACY POOL ASP APPROVAL");
    console.log("=" .repeat(70));

    // Load current state
    const state = loadPrivacyPoolState();
    
    if (state.deposits.length === 0) {
        throw new Error("No deposits found. Run 1-CreateDeposit-BaseSepolia.ts first.");
    }

    console.log(`📊 Current State:`);
    console.log(`  Total deposits: ${state.deposits.length}`);
    console.log(`  ASP updates: ${state.aspHistory.length}`);

    // Determine which deposits to approve
    let depositsToApprove: DepositRecord[];
    
    if (depositIndices && depositIndices.length > 0) {
        // Approve specific deposits
        depositsToApprove = depositIndices.map(index => {
            const deposit = state.deposits.find(d => d.depositIndex === index);
            if (!deposit) {
                throw new Error(`Deposit with index ${index} not found`);
            }
            return deposit;
        });
        console.log(`\n🎯 Approving specific deposits: [${depositIndices.join(', ')}]`);
    } else {
        // Approve all deposits that haven't been approved yet
        depositsToApprove = state.deposits.filter(d => d.status === "deposited");
        if (depositsToApprove.length === 0) {
            console.log(`\n✅ All deposits are already ASP approved!`);
            return;
        }
        console.log(`\n🔄 Approving all pending deposits: ${depositsToApprove.length} deposits`);
    }

    // Display deposits to approve
    console.log(`\n📋 Deposits to approve:`);
    depositsToApprove.forEach(deposit => {
        console.log(`  Index ${deposit.depositIndex}: Label ${deposit.label} (${deposit.status})`);
    });

    // Get all previously approved labels from ASP history
    const allApprovedLabels: string[] = [];
    state.aspHistory.forEach(asp => {
        asp.approvedLabels.forEach(label => {
            if (!allApprovedLabels.includes(label)) {
                allApprovedLabels.push(label);
            }
        });
    });

    // Add new labels from deposits to approve
    const newLabels: string[] = [];
    depositsToApprove.forEach(deposit => {
        if (!allApprovedLabels.includes(deposit.label)) {
            allApprovedLabels.push(deposit.label);
            newLabels.push(deposit.label);
        }
    });

    console.log(`\n🌳 ASP Tree Construction:`);
    console.log(`  Previously approved labels: ${allApprovedLabels.length - newLabels.length}`);
    console.log(`  New labels to add: ${newLabels.length}`);
    console.log(`  Total labels in ASP: ${allApprovedLabels.length}`);

    // Build complete ASP tree
    const allLabelsBigInt = allApprovedLabels.map(l => BigInt(l));
    const aspTree = buildASPTree(allLabelsBigInt);
    const aspRoot = aspTree.root;

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

    // Update the on-chain ASP root
    console.log(`\n📤 Updating on-chain ASP root...`);
    
    const timestamp = new Date().toISOString();
    const mockIPFSCID = `QmASP${Date.now()}TestingOnly1234567890abcdefg`; // Valid IPFS CID format
    
    console.log(`  New ASP root: ${aspRoot}`);
    console.log(`  IPFS CID: ${mockIPFSCID}`);
    
    const updateTx = await walletClient.writeContract({
        address: CONFIG.CONTRACTS.ENTRYPOINT as `0x${string}`,
        abi: ENTRYPOINT_ABI,
        functionName: "updateRoot",
        args: [aspRoot, mockIPFSCID],
    });

    console.log(`  Transaction hash: ${updateTx}`);
    console.log(`  Waiting for confirmation...`);

    const receipt = await publicClient.waitForTransactionReceipt({ hash: updateTx });
    console.log(`  ✅ ASP root updated in block: ${receipt.blockNumber}`);

    // Update state with ASP approval
    const aspRecord: ASPRecord = {
        timestamp,
        root: aspRoot.toString(),
        ipfsCid: mockIPFSCID,
        approvedLabels: allApprovedLabels,
        approvedDepositIndices: depositsToApprove.map(d => d.depositIndex),
        transactionHash: updateTx,
        blockNumber: receipt.blockNumber.toString(),
    };

    state.aspHistory.push(aspRecord);

    // Mark deposits as ASP approved
    depositsToApprove.forEach(deposit => {
        const stateDeposit = state.deposits.find(d => d.depositIndex === deposit.depositIndex);
        if (stateDeposit) {
            stateDeposit.status = "asp_approved";
        }
    });

    // Save updated state
    savePrivacyPoolState(state);

    console.log(`\n✅ ASP APPROVAL SUCCESSFUL!`);
    console.log(`  Approved deposits: ${depositsToApprove.length}`);
    console.log(`  Total ASP labels: ${allApprovedLabels.length}`);
    console.log(`  ASP Root: ${aspRoot}`);
    console.log(`  Transaction: https://sepolia.basescan.org/tx/${updateTx}`);
    
    console.log(`\n🔄 Next Steps:`);
    console.log(`  Deposits are now eligible for withdrawal!`);
    depositsToApprove.forEach(deposit => {
        console.log(`  - npx ts-node scripts/3-Withdraw-BaseSepolia.ts ${deposit.depositIndex}`);
    });

    return aspRecord;
}

// ============ UTILITY FUNCTIONS ============
function displayCurrentState() {
    console.log("\n" + "=" .repeat(70));
    console.log("📊 CURRENT PRIVACY POOL STATE");
    console.log("=" .repeat(70));
    
    const state = loadPrivacyPoolState();
    
    console.log(`Total Deposits: ${state.deposits.length}`);
    console.log(`ASP Updates: ${state.aspHistory.length}`);
    
    if (state.deposits.length > 0) {
        console.log("\nDeposit Status:");
        const statusCounts = state.deposits.reduce((acc, d) => {
            acc[d.status] = (acc[d.status] || 0) + 1;
            return acc;
        }, {} as Record<string, number>);
        
        Object.entries(statusCounts).forEach(([status, count]) => {
            console.log(`  ${status}: ${count}`);
        });
        
        console.log("\nPending ASP Approval:");
        const pending = state.deposits.filter(d => d.status === "deposited");
        if (pending.length === 0) {
            console.log("  ✅ All deposits are ASP approved!");
        } else {
            pending.forEach(deposit => {
                console.log(`  Index ${deposit.depositIndex}: ${deposit.label.slice(0, 20)}...`);
            });
        }
    }
    
    console.log("=" .repeat(70));
}

// ============ MAIN EXECUTION ============
async function main() {
    try {
        const args = process.argv.slice(2);
        
        if (args.includes('--state') || args.includes('-s')) {
            displayCurrentState();
            return;
        }
        
        // Parse deposit indices if provided
        const depositIndices = args
            .map(arg => parseInt(arg))
            .filter(num => !isNaN(num));

        if (args.length > 0 && depositIndices.length === 0) {
            console.error("Invalid arguments. Provide deposit indices as numbers.");
            console.log("\nUsage:");
            console.log("  npx ts-node scripts/2-ApproveASP-BaseSepolia.ts           # Approve all pending");
            console.log("  npx ts-node scripts/2-ApproveASP-BaseSepolia.ts 0 1 2     # Approve specific deposits");
            console.log("  npx ts-node scripts/2-ApproveASP-BaseSepolia.ts --state   # Show current state");
            process.exit(1);
        }

        await approveASP(depositIndices.length > 0 ? depositIndices : undefined);
        
        console.log("\n🎉 ASP approval completed successfully!");
        process.exit(0);
    } catch (error) {
        console.error("\n❌ ASP approval failed:", error);
        process.exit(1);
    }
}

// Run the script if executed directly
if (require.main === module) {
    main();
}

export { approveASP, loadPrivacyPoolState, buildASPTree, CONFIG };
