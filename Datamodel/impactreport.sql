SELECT ba.Naam as ba_naam
     , ba.[Nummer bedrijfstoepassing] as ba_bt_nummer
     , bao.Naam as bao_naam
     , bao.omschrijving as bao_omschrijving
     , xbaoac.bedrijfsapplicatieomgevingid as xbaoac_bedrijfsapplicatieomgevingid
     , xbaoac.applicatiecomponentid as xbaoac_applicatiecomponentid
     , ac.naam as ac_naam
     , ac.type as ac_type
FROM ((Bedrijfsapplicatie ba 
INNER JOIN BedrijfsapplicatieOmgeving bao ON ba.[ID] = bao.[BedrijfsapplicatieID])
INNER JOIN xBedrijfsapplOmg2ApplComp xbaoac ON bao.ID = xbaoac.BedrijfsapplicatieomgevingID)
INNER JOIN applicatiecomponent ac ON xbaoac.applicatiecomponent_id = ac.id;


