# Order Management System - Comprehensive Documentation

## 📋 Table of Contents
1. [System Overview](#system-overview)
2. [Architecture & Data Flow](#architecture--data-flow)
3. [Component Structure](#component-structure)
4. [Critical Business Logic](#critical-business-logic)
5. [Integration Architecture](#integration-architecture)
6. [Deployment Guide](#deployment-guide)
7. [Technical Deep Dive](#technical-deep-dive)

---

## 🎯 System Overview

This is a **full-featured e-commerce Order Management System** built on Salesforce DX that enables:
- Multi-org product synchronization
- Real-time product browsing with search and filtering
- Shopping cart management with draft orders
- Complex checkout with account, contract, and pricebook resolution
- Automated PDF invoice generation
- Bi-directional REST API integrations

**Key Technologies:**
- Salesforce DX
- Lightning Web Components (LWC)
- Apex REST Services
- Visualforce (PDF Generation)
- Named Credentials (Secure Callouts)
- Batch/Scheduled Jobs

---

## 🏗️ Architecture & Data Flow

### **1. Product Synchronization Flow (External → Salesforce)**

