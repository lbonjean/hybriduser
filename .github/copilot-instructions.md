# Copilot Instructions
## language
-  All comments in code and documentation in english
-  Use english for any text output, messages, logs, etc.
-  Use consistent terminology and naming conventions throughout the codebase.
-  Answer to chats in the same language as the question is asked.
## code style
-   Follow established coding standards and best practices for the specific programming language or framework being used.
-   Write clean, readable, and maintainable code with appropriate comments and documentation.
-   Use meaningful variable and function names that accurately describe their purpose.
-   Break down complex functions or methods into smaller, modular components for better readability and reusability.
-   Avoid code duplication by reusing existing functions or creating reusable components.
-   Optimize code for performance and efficiency without sacrificing readability.
-   Handle errors and exceptions gracefully, providing informative error messages and logging where necessary.
-   Write unit tests for critical functions and components to ensure code quality and reliability.
-   Use version control effectively, including meaningful commit messages and branching strategies.
-   avoid unicode characters in powershell scripts. They might run on a system that does not support them.
## security
-   Follow security best practices, such as input validation, output encoding, and secure authentication and authorization mechanisms.
-   Avoid hardcoding sensitive information, such as passwords or API keys, in the codebase.
-   Regularly update dependencies and libraries to address security vulnerabilities.
-   Implement proper access controls and permissions to protect sensitive data and resources.
-   Sanitize user inputs to prevent injection attacks and other security vulnerabilities.
-   Use secure communication protocols (e.g., HTTPS) for data transmission.
-   Regularly review and audit code for security vulnerabilities and address any issues promptly.
## documentation
-   Provide clear and concise documentation for the codebase, including setup instructions, usage guidelines, and API documentation.
-   Use inline comments to explain complex logic or algorithms within the code.
-   Maintain an up-to-date README file that provides an overview of the project, its purpose, and how to get started.
-   Document any third-party libraries or dependencies used in the project, including their versions and licenses.
-   Use diagrams or visual aids to illustrate complex concepts or workflows where applicable.
-   Keep documentation organized and easily accessible for developers and users.
## collaboration
-   Follow established coding standards and best practices for the specific programming language or framework being used.
-   Write clean, readable, and maintainable code with appropriate comments and documentation.
-   Use meaningful variable and function names that accurately describe their purpose.
-   Break down complex functions or methods into smaller, modular components for better readability and reusability.
-   Avoid code duplication by reusing existing functions or creating reusable components.
-   Optimize code for performance and efficiency without sacrificing readability.
-   Handle errors and exceptions gracefully, providing informative error messages and logging where necessary.
-   Write unit tests for critical functions and components to ensure code quality and reliability.
-   Use version control effectively, including meaningful commit messages and branching strategies.
## review
-   When reviewing code, provide constructive feedback that focuses on improving code quality, readability, and maintainability.
-   Identify potential bugs, performance issues, or security vulnerabilities in the code and suggest appropriate fixes or improvements.
-   Ensure that the code adheres to established coding standards and best practices for the specific programming language or framework being used.
-   Review documentation for clarity, accuracy, and completeness, suggesting improvements where necessary.
-   Consider the overall architecture and design of the code, ensuring that it is modular, scalable, and maintainable.
-   Test the code thoroughly to ensure that it functions as intended and meets the specified requirements.
-   Communicate effectively with the code author, asking questions and providing feedback in a respectful and collaborative manner.
## specific instructions
-   When working with Azure Logic Apps, follow best practices for designing and implementing workflows, including using triggers and actions effectively, managing state and data flow, and implementing error handling and retries.
-   When working with Azure Bicep files, follow best practices for infrastructure as code, including using modules for reusable components, managing parameters and variables effectively, and implementing proper resource dependencies and configurations.
-   When working with Azure AD Cloud Sync, follow best practices for synchronizing on-premises directories with Azure AD, including configuring synchronization rules, managing service principals and permissions, and monitoring synchronization jobs
-   Make a commit before making significant changes to the codebase, ensuring that changes are well-documented and can be easily reverted if necessary.
## azure resource naming
-   Use lowercase letters and numbers only.
-   Separate words with hyphens (-) for better readability.
-   Keep names concise but descriptive, ideally under 24 characters.
-   Include the resource type as a suffix (e.g., -vm for virtual machines, -rg for resource groups).
-   Avoid using special characters or spaces.
-   Use a consistent naming convention across all resources in the project.
## cooperate with me
-   Ask clarifying questions if the requirements or context are unclear.
-   Suggest improvements or alternatives if you identify potential issues or better approaches.
-   Provide explanations for your suggestions or code changes to help me understand the reasoning behind them.
-   Be open to feedback and willing to iterate on your suggestions based on my input.
-   Keep the conversation focused on the task at hand, avoiding unrelated topics or distractions.
-   Do not change existing code unless explicitly asked.

