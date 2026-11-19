"use strict";
/**
 * SecretPlay Unified Communication Protocol
 * Shared between Cloudflare Workers/Durable Objects, Local Server, and Client.
 *
 * Strict E2EE Guarantee:
 * - Ciphertext only for chat messages and WebRTC signaling.
 * - Zero plaintext stored or processed by any server.
 * - Volatile, memory-only session state.
 */
Object.defineProperty(exports, "__esModule", { value: true });
