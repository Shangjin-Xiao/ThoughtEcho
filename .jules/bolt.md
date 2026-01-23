## 2024-05-24 - [Partial Object Data Loss Risk]
**Learning:** When optimizing database queries to fetch "partial" objects (excluding large columns) for list views, there is a critical risk of data loss if these partial objects are passed to an editor that saves the object back to the database. The editor might overwrite the missing fields with null.
**Action:** Always ensure the editor fetches the *full* object by ID before allowing a save operation. Implement a "loading" state to block the save button until the full data is retrieved.
