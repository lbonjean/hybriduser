# info
- op een domian controller die draait met een managed identitiy op azure een powershell script draaien dat groepen ophaalt uit een ou.
- Als er in de description van de groep een guid staat dan dien je in entra deze groep op te halen.
- de entra gebruikers zijn gedeeltelijk gesynct met de lokale ad.
# doel
## eerste script
- onderhoud van de leden van de ad groep. Als een lid in de entra groep lokaal bestaat dan dient die toegevoegd te worden aan deze groep
- als een bestaand lid van de AD groep geen lid meer is van de entra groep dient die ook uit de lokale groep verwijderd te worden.
- optie om het scipt vanuit de huidige map te schedulen als een schduled task
- logging voorzien naar de eventlog en naar een bestaande log analytics workspace
## tweede script
- kan je ook nog een powershell script voorzien dat via az cli de nodige graph permissions geeft aan de managed identity
