/**
 * Withdrawal Proof Generator for Privacy Pool
 *
 * This module provides utilities for generating real zero-knowledge proofs
 * for Privacy Pool withdrawal operations using snarkjs and circuit files.
 *
 * Features:
 * - Real ZK proof generation using withdrawal circuits
 * - Merkle tree construction for state and ASP trees
 * - Proof verification using verification keys
 */

import { poseidon } from "maci-crypto/build/ts/hashing.js";
import { LeanIMT } from "@zk-kit/lean-imt";
import * as snarkjs from "snarkjs";
import * as fs from "fs";
import { join, resolve } from "path";

// ============ TYPES ============

export interface Commitment {
    value: bigint;
    label: bigint;
    nullifier: bigint;
    secret: bigint;
}

export interface WithdrawalProofData {
    proof: {
        pi_a: string[];
        pi_b: string[][];
        pi_c: string[];
    };
    publicSignals: string[];
}

export interface CircuitPaths {
    wasmPath: string;
    zkeyPath: string;
    vkeyPath: string;
}

export interface WithdrawalProofArgs {
    existingCommitmentHash: bigint;
    withdrawalValue: bigint;
    context: bigint;
    label: bigint;
    existingValue: bigint;
    existingNullifier: bigint;
    existingSecret: bigint;
    newNullifier: bigint;
    newSecret: bigint;
    stateTreeCommitments: bigint[];
    aspTreeLabels: bigint[];
}


// ============ CONFIGURATION ============

const MAX_TREE_DEPTH = 32;

// Default circuit paths (can be overridden)
const getDefaultCircuitsPath = (): string => {
    // Try to find circuits relative to this script
    const possiblePaths = [
        resolve(__dirname, "../circuits"),
        resolve(process.cwd(), "circuits"),
        resolve(__dirname, "../../circuits"),
    ];

    for (const path of possiblePaths) {
        if (fs.existsSync(path)) {
            return path;
        }
    }

    throw new Error("Cannot find circuits directory. Please specify CIRCUITS_PATH environment variable.");
};

// ============ UTILITY FUNCTIONS ============

export function randomBigInt(): bigint {
    return BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));
}

export function padSiblings(siblings: bigint[], targetDepth: number): bigint[] {
    const paddedSiblings = [...siblings];
    while (paddedSiblings.length < targetDepth) {
        paddedSiblings.push(BigInt(0));
    }
    return paddedSiblings;
}

export function hashCommitment(input: Commitment): [bigint, bigint] {
    const precommitment = poseidon([input.nullifier, input.secret]);
    const nullifierHash = poseidon([input.nullifier]);
    const commitmentHash = poseidon([input.value, input.label, precommitment]);
    return [commitmentHash, nullifierHash];
}

// ============ CIRCUIT FILE MANAGEMENT ============

export function getCircuitPaths(circuitsBasePath?: string): CircuitPaths {
    const basePath = circuitsBasePath || process.env.CIRCUITS_PATH || getDefaultCircuitsPath();

    return {
        wasmPath: join(basePath, "build/withdraw/withdraw.wasm"),
        zkeyPath: join(basePath, "keys/withdraw.zkey"),
        vkeyPath: join(basePath, "keys/withdraw.vkey"),
    };
}

export function verifyCircuitFiles(circuitPaths: CircuitPaths): boolean {
    const missing = Object.entries(circuitPaths).filter(([, path]) => !fs.existsSync(path));

    if (missing.length > 0) {
        console.error("❌ Missing circuit files:");
        missing.forEach(([name, path]) => console.error(`   ${name}: ${path}`));
        return false;
    }

    console.log("✅ All circuit files found");
    return true;
}

// ============ WITHDRAWAL PROOF GENERATOR ============

export class WithdrawalProofGenerator {
    private circuitPaths: CircuitPaths;
    private hash: (a: bigint, b: bigint) => bigint;

    constructor(circuitsBasePath?: string) {
        this.circuitPaths = getCircuitPaths(circuitsBasePath);
        this.hash = (a: bigint, b: bigint) => poseidon([a, b]);

        if (!verifyCircuitFiles(this.circuitPaths)) {
            throw new Error("Circuit files not found. Run circuit setup first.");
        }
    }

    /**
     * Generate a withdrawal proof using snarkjs
     */
    async generateWithdrawalProof(args: WithdrawalProofArgs): Promise<WithdrawalProofData> {
        console.log("🔧 Generating withdrawal proof...");

        const {
            existingCommitmentHash,
            withdrawalValue,
            context,
            label,
            existingValue,
            existingNullifier,
            existingSecret,
            newNullifier,
            newSecret,
            stateTreeCommitments,
            aspTreeLabels,
        } = args;

        // Build Merkle trees
        const { stateTree, aspTree } = this.buildMerkleTrees(stateTreeCommitments, aspTreeLabels);

        // Find indices in trees
        const stateIndex = stateTreeCommitments.indexOf(existingCommitmentHash);
        const aspIndex = aspTreeLabels.indexOf(label);

        if (stateIndex === -1) {
            throw new Error("Existing commitment not found in state tree");
        }
        if (aspIndex === -1) {
            throw new Error("Commitment label not found in ASP tree");
        }

        // Generate Merkle proofs
        const stateProof = stateTree.generateProof(stateIndex);
        const aspProof = aspTree.generateProof(aspIndex);

        // Prepare circuit inputs
        const circuitInputs = this.prepareCircuitInputs({
            withdrawalValue,
            stateProof,
            aspProof,
            context,
            label,
            existingValue,
            existingNullifier,
            existingSecret,
            newNullifier,
            newSecret,
            stateIndex: stateProof.index || stateIndex, // for 1 element index is null
            aspIndex: aspProof.index || aspIndex, // for 1 element index is null
        });

        // Generate proof
        const startTime = Date.now();
        console.log("   🚀 Generating proof with snarkjs...");

        const { proof, publicSignals } = await snarkjs.groth16.fullProve(circuitInputs, this.circuitPaths.wasmPath, this.circuitPaths.zkeyPath);

        const endTime = Date.now();
        console.log(`   ✅ Proof generated in ${endTime - startTime}ms`);

        // Verify proof
        const isValid = await this.verifyWithdrawalProof({ proof, publicSignals });

        if (!isValid) {
            throw new Error("Generated proof failed verification");
        }

        console.log("🎉 SUCCESS: Withdrawal proof generated and verified!");
        return { proof, publicSignals };
    }

    /**
     * Verify a withdrawal proof
     */
    async verifyWithdrawalProof(proofData: WithdrawalProofData): Promise<boolean> {
        console.log("🔍 Verifying withdrawal proof...");

        try {
            const vkey = JSON.parse(fs.readFileSync(this.circuitPaths.vkeyPath, "utf8"));
            const isValid = await snarkjs.groth16.verify(vkey, proofData.publicSignals, proofData.proof as any);

            console.log(`   ${isValid ? "✅ Valid" : "❌ Invalid"} proof`);
            return isValid;
        } catch (error) {
            console.error("   ❌ Verification failed:", error instanceof Error ? error.message : String(error));
            return false;
        }
    }

    // ============ PRIVATE METHODS ============

    private buildMerkleTrees(stateTreeCommitments: bigint[], aspTreeLabels: bigint[]) {
        // Build state tree
        const stateTree = new LeanIMT(this.hash);
        stateTreeCommitments.forEach((commitment) => stateTree.insert(commitment));

        // Build ASP tree
        const aspTree = new LeanIMT(this.hash);
        aspTreeLabels.forEach((label) => aspTree.insert(label));

        return { stateTree, aspTree };
    }

    private prepareCircuitInputs(params: {
        withdrawalValue: bigint;
        stateProof: any;
        aspProof: any;
        context: bigint;
        label: bigint;
        existingValue: bigint;
        existingNullifier: bigint;
        existingSecret: bigint;
        newNullifier: bigint;
        newSecret: bigint;
        stateIndex: number;
        aspIndex: number;
    }) {
        const {
            withdrawalValue,
            stateProof,
            aspProof,
            context,
            label,
            existingValue,
            existingNullifier,
            existingSecret,
            newNullifier,
            newSecret,
            stateIndex,
            aspIndex,
        } = params;

        return {
            withdrawnValue: withdrawalValue.toString(),
            stateRoot: stateProof.root.toString(),
            stateTreeDepth: stateProof.root ? stateProof.siblings.length.toString() : "0",
            ASPRoot: aspProof.root.toString(),
            ASPTreeDepth: aspProof.root ? aspProof.siblings.length.toString() : "0",
            context: context.toString(),
            label: label.toString(),
            existingValue: existingValue.toString(),
            existingNullifier: existingNullifier.toString(),
            existingSecret: existingSecret.toString(),
            newNullifier: newNullifier.toString(),
            newSecret: newSecret.toString(),
            stateSiblings: padSiblings(stateProof.siblings, MAX_TREE_DEPTH).map((s) => s.toString()),
            stateIndex: stateIndex,
            ASPSiblings: padSiblings(aspProof.siblings, MAX_TREE_DEPTH).map((s) => s.toString()),
            ASPIndex: aspIndex,
        };
    }
}
