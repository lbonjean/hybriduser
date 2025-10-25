# Logic App Review Notes

## Datum: December 2024

### Gevonden problemen en oplossingen

#### 1. ✅ Check_if_cloud_managed conditie (OPGELOST)
**Probleem:** Negatieve conditie `NOT (isCloudManaged == true)` was visueel verwarrend
**Oplossing:** Hernoemd naar `Check_if_needs_source_authority_update` met positieve conditie

#### 2. Ongebruikte variabelen
- `errorMessage` variabele wordt geïnitialiseerd maar nooit gebruikt
- `hasError` wordt gezet maar niet nuttig gebruikt

#### 3. ExternalId generatie
- Gebruikt `rand()` functie - werkt wel in deze Logic App versie
- Fallback: `concat(utcNow('yyMMddHHmmss'), string(rand(1000, 9999)))`

#### 4. Parse_admin_unit_response - 404 handling
- 404 is normale response als user niet in admin unit zit
- Huidige oplossing: inline if-statement
- Alternatief: Compose action voor normalisatie

#### 5. Base64 encoding in error logs
```bicep
"ErrorDetails":"\',base64(string(result(\'Process_user_scope\'))),\'"
```
Maakt debugging moeilijk in Log Analytics

### Nog te doen
- [ ] Verwijder ongebruikte `errorMessage` variabele
- [ ] Verwijder lege regels in Check_if_needs_source_authority_update
- [ ] Overweeg base64 encoding te vervangen
- [ ] Verbeter Check_if_hybrid conditie (positief formuleren)

### Belangrijke logica flows
1. **User in admin unit → Hybrid check:**
   - Heeft immutableId? → Check/update source of authority
   - Geen immutableId? → Provision naar AD DS

2. **Source of authority update voorwaarden:**
   - `disableSourceOfAuthorityUpdate` moet false zijn
   - Admin unit naam moet in `allowedAdminUnitNames` staan (of array is leeg)