SELECT ba.Naam as ba_naam
     , ba.[Nummer bedrijfstoepassing] as ba_bt_nummer
     , bao.Naam as bao_naam
     , bao.omschrijving as bao_omschrijving
     , xbaoac.bedrijfsapplicatieomgevingid as xbaoac_bedrijfsapplicatieomgevingid
     , xbaoac.applicatiecomponentid as xbaoac_applicatiecomponentid
     , ac.naam as ac_naam
     , ac.ApplicatieComponentTypeID as ac_type
	 , xacac.applcompsourceid
	 , xacac.applcomptargetid
	 , xacaci.applcompinstid
FROM ((((Bedrijfsapplicatie ba 
INNER JOIN BedrijfsapplicatieOmgeving bao ON ba.[ID] = bao.[BedrijfsapplicatieID])
INNER JOIN xBedrijfsapplOmg2ApplComp xbaoac ON bao.ID = xbaoac.BedrijfsapplicatieomgevingID)
INNER JOIN applicatiecomponent ac ON xbaoac.applicatiecomponentid = ac.id)
LEFT JOIN xApplcomp2Applcomp xacac ON ac.id = xacac.applcompsourceid)
INNER JOIN xApplcomp2ApplcompInstall xacaci ON ((ac.id = xacaci.applcompid) OR (xacac.applcomptargetid = xacaci.applcompid));

