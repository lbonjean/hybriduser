# SCIM Payload Mapping voor Entra ID naar AD DS

## Probleem analyse

### Issue 1: employeeID constraint violation
**Fout**: `ConstraintViolation-AtrErr: CONSTRAINT_ATT_TYPE - employeeID`
**Oorzaak**: De Entra ID GUID (36 characters) werd gebruikt als `externalId`, maar AD DS employeeID veld heeft een maximale lengte van 16 characters.
**Oplossing**: Gebruik `userPrincipalName` als `externalId` in plaats van de user GUID.

### Issue 2: Source identifier empty
**Fout**: `Source identifier of an entry cannot be empty`
**Oorzaak**: Het `externalId` veld was volledig verwijderd uit de SCIM payload.
**Oplossing**: Het `externalId` veld is **verplicht** voor de synchronization engine - het identificeert de bron.

## Correcte SCIM Mapping

### Entra ID → SCIM Property Mapping

| Entra ID Property | SCIM Property | Opmerking |
|------------------|---------------|-----------|
| `userPrincipalName` | `externalId` | **Verplicht** - source identifier (max 256 chars) |
| `userPrincipalName` | `userName` | Primaire username |
| `displayName` | `displayName` | Volledige naam |
| `givenName` | `name.givenName` | Voornaam |
| `surname` | `name.familyName` | Achternaam |
| `mail` of `userPrincipalName` | `emails[0].value` | Email adres |
| - | `emails[0].type` | Hardcoded: `"work"` |
| - | `emails[0].primary` | Hardcoded: `true` |
| - | `active` | Hardcoded: `true` |

### Te vermijden velden

❌ **NIET gebruiken**:
- `externalId` = user.id (GUID) → Te lang voor AD DS employeeID
- `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.employeeNumber` = user.id → Te lang

### Minimale werkende payload

```json
{
  "schemas": [
    "urn:ietf:params:scim:api:messages:2.0:BulkRequest"
  ],
  "Operations": [
    {
      "method": "POST",
      "bulkId": "<guid>",
      "path": "/Users",
      "data": {
        "schemas": [
          "urn:ietf:params:scim:schemas:core:2.0:User",
          "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
        ],
        "externalId": "user@domain.com",
        "userName": "user@domain.com",
        "displayName": "John Doe",
        "name": {
          "givenName": "John",
          "familyName": "Doe"
        },
        "emails": [
          {
            "value": "user@domain.com",
            "type": "work",
            "primary": true
          }
        ],
        "active": true,
        "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User": {}
      }
    }
  ],
  "failOnErrors": null
}
```

## Optionele velden voor uitbreiding

Wanneer meer Entra ID velden beschikbaar zijn, kunnen deze toegevoegd worden:

### SCIM Core User Schema
- `nickName` → Entra ID `mailNickname`
- `title` → Entra ID `jobTitle`
- `preferredLanguage` → Entra ID `preferredLanguage`
- `locale` → Entra ID `usageLocation`
- `phoneNumbers[].value` → Entra ID `businessPhones[0]`, `mobilePhone`

### SCIM Enterprise User Extension
- `department` → Entra ID `department`
- `organization` → Entra ID `companyName`
- `costCenter` → Entra ID custom attribute
- `division` → Entra ID custom attribute
- `manager.value` → Entra ID `manager.id` (zou ook userPrincipalName moeten zijn!)

## Graph API $select voor volledige sync

Voor een complete sync, haal de volgende velden op:

```
$select=id,userPrincipalName,displayName,givenName,surname,mail,mailNickname,jobTitle,department,companyName,businessPhones,mobilePhone,preferredLanguage,usageLocation,onPremisesImmutableId,onPremisesSyncEnabled
```

## Logic App implementatie

De Logic App `Get_user_details` action moet minimaal deze velden ophalen:
- `id` (voor intern gebruik)
- `userPrincipalName` (externalId + userName)
- `displayName`
- `givenName`
- `surname`
- `mail`
- `onPremisesImmutableId` (hybrid check)
- `onPremisesSyncEnabled` (hybrid check)

## Test procedure

1. Update test user in Entra ID met alle gewenste velden
2. Run `.\test-scim-upload.ps1` om payload te testen
3. Check provisioning logs in Azure Portal (Entra ID > Enterprise Apps > API-driven provisioning app > Provisioning logs)
4. Verify user creation in AD DS
5. Als succesvol, deploy Logic App en test met notification

## Status

✅ **Werkend**: userPrincipalName als externalId, minimale velden
⏳ **In progress**: Uitgebreide velden mapping testen
🔜 **Todo**: Manager mapping, custom attributes, phone numbers
