# Appcircle _Testinium Upload App_ component

The **Testinium Upload App** component enables uploading mobile applications to the [Testinium](https://testinium.com/) platform for automated testing directly from Appcircle. This step serves as a prerequisite for executing test plans, enabling efficient and automated testing directly within the Appcircle environment.

## Required Inputs

- `AC_TESTINIUM_APP_PATH`: Full path of the build. For example $AC_EXPORT_DIR/Myapp.ipa.
- `AC_TESTINIUM_USERNAME`: Testinium username.
- `AC_TESTINIUM_PASSWORD`: Testinium password.
- `AC_TESTINIUM_PROJECT_ID`: Testinium project ID.
- `AC_TESTINIUM_COMPANY_ID`: Testinium company ID.
- `AC_TESTINIUM_TIMEOUT`: Testinium plan timeout in minutes.
- `AC_TESTINIUM_MAX_API_RETRY_COUNT`: Determine max repetition in case of Testinium platform congestion or API errors.

## Optional Inputs

- `AC_TESTINIUM_ENTERPRISE_BASE_URL`: The base URL for Testinium Enterprise. This is required if you are using Testinium Enterprise. Only for Testinium cloud users, this input is not mandatory.

## Outputs

- `AC_TESTINIUM_UPLOADED_APP_ID`: The unique identifier for the application uploaded to Testinium. This ID is used to select the uploaded application on **Testinium Run Test Plan** step.
- `AC_TESTINIUM_APP_OS`: The operating system of the uploaded application, either iOS or Android. This helps to run the test plan according to the platform OS in **Testinium Run Test Plan** step.
