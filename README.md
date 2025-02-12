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