# Order Management System

This is an Order Management System built on Salesforce DX. It allows users to browse products, add them to a cart, checkout, and generate invoices. The system integrates with external servers for product data and file handling.

## Project Overview

This system is designed to manage orders from product browsing to invoice generation. It features a modern user interface with Lightning Web Components and robust backend Apex classes that handle complex business logic including order creation, product synchronization, and PDF generation.

## Hierarchical File Structure

```
force-app/main/default/
├── classes/
│   ├── CheckOutController.cls
│   ├── CheckOutController.cls-meta.xml
│   ├── FileService.cls
│   ├── FileService.cls-meta.xml
│   ├── InvoicePDFController.cls
│   ├── InvoicePDFController.cls-meta.xml
│   ├── ProductController.cls
│   ├── ProductController.cls-meta.xml
│   ├── ProductPBEServices.cls
│   ├── ProductPBEServices.cls-meta.xml
│   ├── ProductService.cls
│   ├── ProductService.cls-meta.xml
│   ├── ProductSyncBatch.cls
│   ├── ProductSyncBatch.cls-meta.xml
│   ├── ProductSyncScheduler.cls
│   └── ProductSyncScheduler.cls-meta.xml
├── lwc/
│   ├── checkoutPage/
│   │   ├── checkoutPage.css
│   │   ├── checkoutPage.html
│   │   ├── checkoutPage.js
│   │   └── checkoutPage.js-meta.xml
│   ├── productCard/
│   │   ├── productCard.css
│   │   ├── productCard.html
│   │   ├── productCard.js
│   │   └── productCard.js-meta.xml
│   └── productInformationDisplay/
│       ├── productInformationDisplay.css
│       ├── productInformationDisplay.html
│       ├── productInformationDisplay.js
│       └── productInformationDisplay.js-meta.xml
├── pages/
│   ├── InvoicePdf.page
│   └── InvoicePdf.page-meta.xml
└── manifest/
    └── package.xml
```

## Detailed File Structure Explanation

### Apex Classes (force-app/main/default/classes/)

These are server-side logic files written in Apex, Salesforce's programming language. They handle business logic, data manipulation, and integrations with external systems.

#### Core Business Logic Classes

1. **CheckOutController.cls**
   - **Purpose**: The main checkout manager that handles order creation from shopping cart items
   - **Key Functions**:
     - Creates new orders with customer information
     - Manages product quantities and prices
     - Generates and saves PDF invoices
     - Handles account creation and lookup
   - **How it Works**: When a user places an order, this class takes all the cart items, validates them, creates an Order record in Salesforce, adds Order Items, calculates the total, and generates a PDF invoice that's saved to the customer's account

2. **InvoicePDFController.cls**
   - **Purpose**: Controls the data displayed on the invoice PDF page
   - **Key Functions**:
     - Fetches order details and line items
     - Calculates totals (subtotal, tax, total)
   - **How it Works**: This controller connects to the Visualforce page to display the correct order information when generating invoices

3. **ProductController.cls**
   - **Purpose**: Manages product data for the user interface
   - **Key Functions**:
     - Fetches products from Salesforce with search and filtering
     - Handles product families for categorization
     - Gets pricing information from both local and remote systems
   - **How it Works**: When users browse products, this class retrieves them from Salesforce and provides pricing information, either from the local system or from an external server

#### Integration Classes

4. **FileService.cls**
   - **Purpose**: Receives files from external systems and stores them in Salesforce
   - **Key Functions**:
     - Accepts file uploads via REST API
     - Stores files as ContentVersion records in Salesforce
   - **How it Works**: When an external system needs to send a file to Salesforce, it uses this service to receive and store it

5. **ProductPBEServices.cls**
   - **Purpose**: REST API for external systems to get product pricing
   - **Key Functions**:
     - Returns unit price for specific products
   - **How it Works**: Used by external systems to get current pricing information for products

6. **ProductService.cls**
   - **Purpose**: REST API for external systems to get full product details
   - **Key Functions**:
     - Returns complete product information
   - **How it Works**: Provides external systems with all product data needed for integration

#### Data Synchronization Classes

7. **ProductSyncBatch.cls**
   - **Purpose**: Background job that synchronizes products from external systems
   - **Key Functions**:
     - Pulls product data from external server
     - Updates or creates Product2 and PricebookEntry records in Salesforce
   - **How it Works**: Runs automatically to keep product information in Salesforce up-to-date with the external system

8. **ProductSyncScheduler.cls**
   - **Purpose**: Schedules the product synchronization job
   - **Key Functions**:
     - Sets up automatic running of the ProductSyncBatch job
   - **How it Works**: Ensures the product synchronization happens regularly without manual intervention

### Lightning Web Components (force-app/main/default/lwc/)

These are modern UI components using JavaScript, HTML, and CSS that provide the user interface experience.

1. **checkoutPage**
   - **Purpose**: Main checkout form where customers complete their purchase
   - **Files**:
     - **checkoutPage.html**: Defines the form layout and structure
     - **checkoutPage.js**: Handles form interactions and calls backend services
     - **checkoutPage.css**: Makes the form look nice and professional
   - **How it Works**: Customers enter their information, select products, and submit their order through this component

2. **productCard**
   - **Purpose**: Shows individual products in a visually appealing card format
   - **Files**:
     - **productCard.html**: Displays product information in a card
     - **productCard.js**: Gets product data from the backend
     - **productCard.css**: Styles the product cards
   - **How it Works**: Used to display multiple products in a grid or list format

3. **productInformationDisplay**
   - **Purpose**: Shows detailed information about a specific product
   - **Files**:
     - **productInformationDisplay.html**: Displays detailed product information
     - **productInformationDisplay.js**: Loads the detailed product data
     - **productInformationDisplay.css**: Styles the detailed view
   - **How it Works**: When users click on a product card, they can see more details about that specific product

### Visualforce Pages (force-app/main/default/pages/)

These are traditional Salesforce pages that handle PDF generation.

1. **InvoicePdf.page**
   - **Purpose**: Generates PDF invoices for orders
   - **How it Works**: Uses the InvoicePDFController to get order data and formats it into a printable PDF

### Deployment Configuration (manifest/package.xml)

1. **package.xml**
   - **Purpose**: Defines what components to deploy to Salesforce
   - **How it Works**: Tells Salesforce which files to include when deploying this application

## How the System Works Together

1. **Product Browsing**: Users see products through the productCard component, which gets data from ProductController
2. **Adding to Cart**: Products are added to a session-based cart in the browser
3. **Checkout Process**: Users fill out the checkoutPage form, which calls CheckOutController to create the order
4. **Order Creation**: CheckOutController creates an Order record and Order Items in Salesforce
5. **Invoice Generation**: A PDF invoice is automatically created and saved to the customer's account
6. **Data Synchronization**: Regular background jobs keep product information up-to-date from external systems

## Getting Started

1. Clone the repo
2. Run `sfdx force:source:deploy` to deploy
3. Use LWCs in Lightning pages or Experience Builder

This system provides a complete order management solution with strong integration capabilities for connecting with external systems. The modular design makes it easy to maintain and extend.
