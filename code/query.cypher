//Import podataka
//Za lokalni DB koristimo "file:///EmployeeMovement.csv"
//Za AuraDB koristimo "https://raw.githubusercontent.com/infobip-task/workforcetenure/main/dataset/EmployeeMovement.csv"

//Varijanta 1 - X postaje prazan
LOAD CSV WITH HEADERS FROM "file:///EmployeeMovement.csv" AS csvLine FIELDTERMINATOR ';'
CREATE
(
e:Employee {EmployeeID: csvLine.EmployeeID, 
StartOfContract: date(csvLine.StartOfContract), 
EndOfContract: date(CASE csvLine.EndOfContract WHEN "X" THEN null ELSE csvLine.EndOfContract END)}
)


//Varijanta 2 - X postaje današnji datum - ovo je korišteno
LOAD CSV WITH HEADERS FROM "file:///EmployeeMovement.csv" AS csvLine FIELDTERMINATOR ';'
CREATE
(
e:Employee {EmployeeID: csvLine.EmployeeID, 
StartOfContract: date(csvLine.StartOfContract), 
EndOfContract: date(CASE csvLine.EndOfContract WHEN "X" THEN date() ELSE csvLine.EndOfContract END)}
)


//Varijanta 3 - X postaje zadnji dan tekućeg mjeseca
LOAD CSV WITH HEADERS FROM "file:///EmployeeMovement.csv" AS csvLine FIELDTERMINATOR ';'
CREATE
(
e:Employee {EmployeeID: csvLine.EmployeeID,
StartOfContract: date(csvLine.StartOfContract),
EndOfContract: date(CASE csvLine.EndOfContract WHEN "X" THEN date({year: date().year, month: date().month+1, day:1})-duration({days:1})
ELSE csvLine.EndOfContract END)}
)


//Stvaranje veza između zaposlenika koji su bili zaposlenici tvrtke u istom periodu
MATCH(e1:Employee)
MATCH(e2:Employee)
WHERE id(e1)<id(e2)
MERGE(e1)-[w:WORKED_WITH]-(e2)
SET
w.StartedWorkingTogether = CASE WHEN e1.StartOfContract > e2.StartOfContract THEN e1.StartOfContract ELSE e2.StartOfContract END,
w.EndedWorkingTogether = CASE WHEN e1.EndOfContract < e2.EndOfContract THEN e1.EndOfContract ELSE e2.EndOfContract END
RETURN e1.EmployeeID, e2.EmployeeID, w.StartedWorkingTogether, w.EndedWorkingTogether


//Napomena - u Neo4j mreža je po defaultu pohranjena kao usmjerana, potrebno je analizirati neusmjerenu mrežu jer između zaposlenika postoji dvosmjerna komunikacija
//Virtualizacija mreže (native projection) u jednostavnom obliku bez atributa - ne koristimo u ovom slučaju
CALL gds.graph.project('graphEmployees', 'Employee', {WORKED_WITH: {orientation: 'UNDIRECTED'}})


//Virtualizacija mreže (cypher projection) sa svim atributima (kad se koristi Cypher projection po defaultu ne možemo virtualizirati neusmjerenu mrežu putem propertya)
//Za neusmjerenu mrežu potrebno je izbaciti strelice za smjer kod definiranja relationshipa
//Primjer virtualizacije za sve zaposlenike koji su zajedno radili 2010.
CALL gds.graph.project.cypher
(
'graphEmployees',
'MATCH (e:Employee) RETURN id(e) AS id',
'MATCH (e1:Employee)-[w:WORKED_WITH]-(e2:Employee) WHERE (w.StartedWorkingTogether).year <=2010 AND (w.EndedWorkingTogether).year >=2010 RETURN id(e1) AS source, id(e2) AS target'
)
 

//Napomena - ako smo virtualizirali usmjerenu mrežu, kod izračuna metrika možemo definirati da je mreža neusmjerena ako koristimo native projection.
//Ako koristimo cypher projection to nije potrebno
//Izračun metrike centraliteta - degree
CALL gds.degree.write
(
'graphEmployees',
{writeProperty: 'Degree_2010-31-12'}
)
YIELD nodePropertiesWritten, centralityDistribution
RETURN nodePropertiesWritten, centralityDistribution.min AS minimumScore, centralityDistribution.mean AS meanScore, centralityDistribution.max AS maxScore


//Izračun metrike centraliteta - eigenvector
CALL gds.eigenvector.write
(
'graphEmployees',
{writeProperty: 'Eigenvector_2010-31-12'}
)
YIELD nodePropertiesWritten, centralityDistribution
RETURN nodePropertiesWritten, centralityDistribution.min AS minimumScore, centralityDistribution.mean AS meanScore, centralityDistribution.max AS maxScore


//Izračun metrike centraliteta - betweenness
CALL gds.betweenness.write
(
'graphEmployees',
{writeProperty: 'Betweenness_2010-31-12'}
)
YIELD nodePropertiesWritten, centralityDistribution
RETURN nodePropertiesWritten, centralityDistribution.min AS minimumScore, centralityDistribution.mean AS meanScore, centralityDistribution.max AS maxScore


//Detekcija zajednica unutar mreže po Louvain metodi
CALL gds.louvain.write
(
'graphEmployees',
{writeProperty: 'Louvain_2010-31-12'}
)
YIELD communityCount, modularity, modularities


//Brisanje mreže iz memorije
CALL gds.graph.drop('graphEmployees')


//Export podataka za vizualizaciju
MATCH (e:Employee)
WITH collect(e) AS employee
CALL apoc.export.csv.data(employee, [], "EmployeeMetrics.csv", {})
YIELD file, source, format, nodes, relationships, properties, time, rows, batchSize, batches, done, data
RETURN file, source, format, nodes, relationships, properties, time, rows, batchSize, batches, done, data
