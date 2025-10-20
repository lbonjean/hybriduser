# Entra ID naar SCIM 2.0 Field Mapping

## Datum: 2025-10-18

## Test User: test20251018@bas-services.nl (53453e32-55f4-425c-805c-ea30d072de7a)

## Beschikbare Entra ID velden

```json
{
  "id": "53453e32-55f4-425c-805c-ea30d072de7a",
  "userPrincipalName": "test20251018@bas-services.nl",
  "displayName": "Testtest20251018-FINAL",
  "givenName": "test",
  "surname": "gebruiker",
  "mail": null,
  "mailNickname": "test20251018",
  "jobTitle": null,
  "department": null,
  "companyName": null,
  "businessPhones": [],
  "mobilePhone": null,
  "preferredLanguage": null,
  "usageLocation": null,
  "employeeId": null,
  "city": null,
  "country": null,
  "postalCode": null,
  "state": null,
  "streetAddress": null,
  "officeLocation": null,
  "onPremisesImmutableId": null,
  "onPremisesSyncEnabled": null
}
```

## SCIM 2.0 Schema Mapping

### Verplichte velden (altijd versturen)

| Entra ID Veld | SCIM Veld | Type | Opmerking |
|---------------|-----------|------|-----------|
| `get-date -format 'yyyyMMddhhmmss'` | `externalId` | string | **Unieke timestamp** - voorkomt employeeID constraint |
| `userPrincipalName` | `userName` | string | Primaire login naam |
| `displayName` | `displayName` | string | Volledige naam |
| `givenName` | `name.givenName` | string | Voornaam |
| `surname` | `name.familyName` | string | Achternaam |
| `mail` of `userPrincipalName` | `emails[0].value` | string | Email adres (fallback naar UPN) |
| - | `emails[0].type` | string | Hardcoded: `"work"` |
| - | `emails[0].primary` | boolean | Hardcoded: `true` |
| - | `active` | boolean | Hardcoded: `true` |

### SCIM Core User Schema - Optionele velden

| Entra ID Veld | SCIM Veld | Type | Opmerking |
|---------------|-----------|------|-----------|
| `mailNickname` | `nickName` | string | Korte naam / alias |
| `jobTitle` | `title` | string | Functie titel |
| `preferredLanguage` | `preferredLanguage` | string | Taalvoorkeur (bijv. "nl-NL") |
| `usageLocation` | `locale` | string | Landcode (bijv. "NL") |
| `businessPhones[0]` | `phoneNumbers[0].value` | string | Zakelijk telefoonnummer |
| - | `phoneNumbers[0].type` | string | Hardcoded: `"work"` |
| `mobilePhone` | `phoneNumbers[1].value` | string | Mobiel telefoonnummer |
| - | `phoneNumbers[1].type` | string | Hardcoded: `"mobile"` |
| `streetAddress` | `addresses[0].streetAddress` | string | Straat + huisnummer |
| `postalCode` | `addresses[0].postalCode` | string | Postcode |
| `city` | `addresses[0].locality` | string | Woonplaats |
| `state` | `addresses[0].region` | string | Provincie/staat |
| `country` | `addresses[0].country` | string | Land |
| - | `addresses[0].type` | string | Hardcoded: `"work"` |
| `officeLocation` | `addresses[1].formatted` | string | Kantoorlocatie als formatted address |
| - | `addresses[1].type` | string | Hardcoded: `"work"` |

### SCIM Enterprise User Extension - Optionele velden

| Entra ID Veld | SCIM Veld | Type | Opmerking |
|---------------|-----------|------|-----------|
| `employeeId` | `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.employeeNumber` | string | **Belangrijk**: Entra employeeId → SCIM employeeNumber |
| `department` | `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.department` | string | Afdeling |
| `companyName` | `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.organization` | string | Bedrijfsnaam |
| - | `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.costCenter` | string | Kostencenter (niet beschikbaar in base Entra) |
| - | `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.division` | string | Divisie (niet beschikbaar in base Entra) |

**Opmerking**: Manager mapping is complexer - vereist lookup van manager's externalId:
- Entra: `manager` (relationeel veld, vereist separate Graph call)
- SCIM: `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User.manager.value` (moet externalId of ID van manager zijn)

## Voorgestelde implementatie strategie

### Fase 1: Minimale velden (HUIDIGE STATUS ✅)
- externalId (timestamp)
- userName
- displayName
- name (givenName, familyName)
- emails
- active

### Fase 2: Uitbreiding met beschikbare optionele velden
Alleen toevoegen als waarde `niet null` is:

**Core User uitbreiding**:
- nickName ← mailNickname (altijd beschikbaar)
- title ← jobTitle
- preferredLanguage
- locale ← usageLocation
- phoneNumbers (businessPhones, mobilePhone)
- addresses (streetAddress, postalCode, city, state, country, officeLocation)

**Enterprise User uitbreiding**:
- employeeNumber ← employeeId **BELANGRIJK VOOR USER**
- department
- organization ← companyName

### Fase 3: Manager relatie (optioneel)
- Vereist extra Graph call: `GET /users/{id}/manager`
- Map naar `manager.value` (gebruik manager's externalId = timestamp of userPrincipalName)

## Graph API $select voor optimale sync

```
$select=id,userPrincipalName,displayName,givenName,surname,mail,mailNickname,jobTitle,department,companyName,businessPhones,mobilePhone,preferredLanguage,usageLocation,employeeId,city,country,postalCode,state,streetAddress,officeLocation,onPremisesImmutableId,onPremisesSyncEnabled
```

## Implementatie in Logic App

### Get_user_details - URI parameter
```bicep
uri: 'https://graph.microsoft.com/v1.0/users/@{variables(\'userId\')}?$select=id,userPrincipalName,displayName,givenName,surname,mail,mailNickname,jobTitle,department,companyName,businessPhones,mobilePhone,preferredLanguage,usageLocation,employeeId,city,country,postalCode,state,streetAddress,officeLocation,onPremisesImmutableId,onPremisesSyncEnabled'
```

### Parse_user_details - Schema
Alle velden moeten `nullable` zijn (type: `['string', 'null']` of `['array', 'null']`):

```bicep
properties: {
  id: { type: 'string' }
  userPrincipalName: { type: 'string' }
  displayName: { type: 'string' }
  givenName: { type: ['string', 'null'] }
  surname: { type: ['string', 'null'] }
  mail: { type: ['string', 'null'] }
  mailNickname: { type: ['string', 'null'] }
  jobTitle: { type: ['string', 'null'] }
  department: { type: ['string', 'null'] }
  companyName: { type: ['string', 'null'] }
  businessPhones: { type: ['array', 'null'] }
  mobilePhone: { type: ['string', 'null'] }
  preferredLanguage: { type: ['string', 'null'] }
  usageLocation: { type: ['string', 'null'] }
  employeeId: { type: ['string', 'null'] }
  city: { type: ['string', 'null'] }
  country: { type: ['string', 'null'] }
  postalCode: { type: ['string', 'null'] }
  state: { type: ['string', 'null'] }
  streetAddress: { type: ['string', 'null'] }
  officeLocation: { type: ['string', 'null'] }
  onPremisesImmutableId: { type: ['string', 'null'] }
  onPremisesSyncEnabled: { type: ['boolean', 'null'] }
}
```

### Provision_user_to_ADDS - SCIM payload body

**Minimale versie (Fase 1)**:
```bicep
data: {
  schemas: [
    'urn:ietf:params:scim:schemas:core:2.0:User'
    'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User'
  ]
  externalId: '@{utcNow(\'yyyyMMddHHmmss\')}'
  userName: '@{body(\'Parse_user_details\')?[\'userPrincipalName\']}'
  displayName: '@{body(\'Parse_user_details\')?[\'displayName\']}'
  name: {
    givenName: '@{body(\'Parse_user_details\')?[\'givenName\']}'
    familyName: '@{body(\'Parse_user_details\')?[\'surname\']}'
  }
  emails: [
    {
      value: '@{if(empty(body(\'Parse_user_details\')?[\'mail\']), body(\'Parse_user_details\')?[\'userPrincipalName\'], body(\'Parse_user_details\')?[\'mail\'])}'
      type: 'work'
      primary: true
    }
  ]
  active: true
  'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User': {}
}
```

**Uitgebreide versie (Fase 2)** - met conditionele velden:

Logic App ondersteunt **geen** conditionals in de data sectie direct. Oplossing:
1. Gebruik `if(empty(...), null, ...)` voor optionele string velden
2. Arrays moeten pre-built zijn in een aparte Compose action

## Aanbeveling voor implementatie

**Nu meteen doen**:
1. Update test script (`test-scim-upload.ps1`) met **alle beschikbare velden** uit mapping
2. Test met user die `employeeId` heeft ingevuld
3. Valideer dat alle velden correct overgekomen zijn in AD DS

**Daarna**:
1. Update Logic App (`logicapp.bicep`) met volledige field mapping
2. Deploy en test end-to-end

## Belangrijke waarschuwing: externalId consistentie

⚠️ **PROBLEEM**: Als je `externalId = timestamp` gebruikt, dan is deze **ELKE keer anders**!

Dit betekent:
- Eerste sync: User wordt aangemaakt met externalId = "20251018073015"
- Update later: User wordt gezocht met externalId = "20251018080530" → **NIET GEVONDEN** → **NIEUWE USER**

**OPLOSSING**:
1. **Optie A**: Gebruik `userPrincipalName` als externalId (consistent, uniek)
2. **Optie B**: Genereer timestamp **1x bij eerste provisioning** en sla op in custom attribuut
3. **Optie C**: Gebruik Entra `id` (GUID) als externalId EN map naar een ander AD veld (niet employeeID)

**Mijn voorkeur**: **Optie A** - `externalId = userPrincipalName`

Dit is:
- ✅ Consistent (verandert zelden)
- ✅ Uniek per user
- ✅ Kort genoeg (meestal 30-50 chars)
- ✅ Geen employeeID constraint conflict
- ✅ Makkelijk te debuggen

Als je `employeeId` uit Entra wilt syncen, gebruik dan:
```
"urn:ietf:params:scim:schemas:extension:enterprise:2.0:User": {
  "employeeNumber": "@{body('Parse_user_details')?['employeeId']}"
}
```

## Status

- ✅ Entra velden geïnventariseerd
- ✅ SCIM mapping gedefinieerd
- ⏳ Test script updaten met volledige mapping
- ⏳ Logic App updaten met volledige mapping
- ⏳ End-to-end test met alle velden
