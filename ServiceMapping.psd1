@{
    ActiveDirectory=@{
        server="DC01.contoso.com"
        credentialType = 'DomainAdmin'
        args=@{
            DomainName="contoso.com"
        }
    }
    MSSQL=@{
        server="DB01.contoso.com"
        credentialType = 'ServerAdmin'
        args=@{
        }
    }
    Openfire=@{
        server="Chat01.contoso.com"
        credentialType = 'ServerAdmin'
        args=@{
        }
    }
}