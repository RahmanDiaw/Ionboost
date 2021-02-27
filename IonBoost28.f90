program Ionboost

     use iso_fortran_env, only: int32, real32, int64, real64
     use mod_share
     use mod_math, only: Thot_, Tcold_, gauss
     use mod_io, only: read_check_init_conditions
     
     implicit none


!*         1 - Set initial conditions and determine plasma size

    call read_check_init_conditions('IonBoost28.in')

!!!! Put this in separate module file so we can change the initial potential
!!!!!!!

!*  1.3 conditions initiales et estimation du potentiel phi initial
    
    Tnorm=T_MeV/.511d0
    e0=0.5*Tnorm*(1.+9.*Tnorm/4.+3.*Tnorm*Tnorm/4.)/(1.+3.*Tnorm/2.+3.*Tnorm*Tnorm/8.)
    Tn0=2.*e0

    Th=Thmax*Thot_(0.d0)
    Tc=Tcmax*Tcold_(0.d0)
      if(Th.eq.0.d0)then
         write(*,*) 'la temperature chaude ne doit pas s''annuler'
         stop
      endif


    phi(ncell)=(n0cold*Tc+n0hot*Th)/(n0cold+n0hot)
    E(ncell)=sqrt(2.*(n0cold*Tc*exp(-phi(ncell)/Tc) +n0hot*Th*exp(-phi(ncell)/Th)))
    alpha=E(ncell)/phi(ncell)

    mixp=0.d0



    do i = 0,ncell
       xt(i)=x0(i)
       v(i)=0.d0
       phi(i)=phi(ncell)*exp(alpha*(x0(i)-x0(ncell)))
       charge(i)=1.d0
    end do

    do i =ncell+1,ntotal
        v(i)=0.
        ni(i)=1.d-12
    enddo


    E(0)=0.d0
    gradnh(0)=0.d0
    gradnc(0)=0.d0
    time=0.d0
    dt=dti
    nhm2=n0hot
    nhm1=n0hot
    Thm2=Thmax
    Thm1=Thm2
    Tcm2=Tc
    Tcm1=Tc
    Whot1=0.d0
    Whot2=0.d0
    Wcold=0.d0
    idico=0

!!!!!!!!!!!
!!!!!!!!!!!

!*               2 - boucle temporelle
    do 100 itime=1,itmax

        if(itime.le.3) then
           iter=iter0
        else
           iter=iter1
        endif


!*         2.1 determination ou estimation des temperatures et de n0hot
!*             et calcul de la nouvelle densite ionique
!*    2.1.1 - determination des temperatures dans le cas ou leur
!*             dependance est fixee par les fonctions Thot et Tcold

        Thold=Th
        Tcoold=Tc
        if(.not.En_cons)then
               Th=Thmax*Thot_(time)
               Tc=Tcmax*Tcold_(time)
               idico=0
               if(Th.eq.0.d0)then
                    write(*,*) 'la temperature chaude ne doit pas s''annuler'
                    stop
               endif
               if((Th-Thold)/Thold.gt.0.05d0) then
                  iter=iter0
               endif
               if((Th-Thold)/Thold.lt.-0.05d0) then
                  iter=iter0
                  endif
        endif

            
!    *    2.1.2 - estimation de la modification de n0hot liee a la
!    *             conservation du nombre d'electrons chauds

        if(nb_cons)then
           nhm3=nhm2
           nhm2=nhm1
           nhm1=n0hot
           n0hot=3.d0*nhm1-3.d0*nhm2+nhm3
        endif


!*    2.1.3 - estimation de la modification de Th et Tc liee a la
!*              conservation de l'energie

        if(En_cons)then
           Thm3=Thm2
           Thm2=Thm1
           Thm1=Th
           Th=3.d0*Thm1-3.d0*Thm2+Thm3
           Tcm3=Tcm2
           Tcm2=Tcm1
           Tcm1=Tc
           Tc=3.d0*Tcm1-3.d0*Tcm2+Tcm3
        endif
        
    !*****************************
        if(itime.eq.(itime/nsort)*nsort) then
           write(*,*)
           write(*,*)time
        endif


!    *    2.1.4 - mise en memoire des anciennes valeurs de la densite
!    *             electronique, du potentiel, du champ electrique,
!    *             des gradients de densite electronique,
!    *             et de la position dans la gaine vide d'ions

          if(itime.gt.1) then
             do i=0,ntotal
                nhotold(i)=nhot(i)
                ncoldold(i)=ncold(i)
                phiold(i)=phi(i)
                Eold(i)=E(i)
                ghold(i)=gradnh(i)
                gcold(i)=gradnc(i)
             enddo

             do i=ncell+1,ntotal
                xtold(i)=xt(i)
             enddo
             do i=1,ntotal
                dxtold(i)=dxt(i)
             enddo
             Whot1old=Whot1
             Whot2old=Whot2
             Wcoldold=Wcold
          endif


!*     2.1.5 calcul de la nouvelle densite ionique
    
        do i = 1,ncell
           dxt(i)=xt(i)-xt(i-1)
        end do
        
        ni(0)=qiSS(0)/dxt(1)
    
        do i = 1,ncell-1
           ni(i)=2.d0*qiSS(i)/(dxt(i)+dxt(i+1))
        end do
        
        ni(ncell)=2.d0*qiSS(ncell)/dxt(ncell)/(1.d0+2.d0*dxt(ncell)/dxt(ncell-1)-dxt(ncell-1)/dxt(ncell-2))

        do i = 1,ncell
           ni1s2(i)=(ni(i-1)+ni(i))/2.d0
        end do



!    *       2.2 - iteration pour le calcul de phi, Th, Tc

        do 10 iphi=1,iter
!        do iphi=1,iter

!    *    2.2.1 - construction des tableaux a,b,c, et f

        neh=n0hot*exp(-phi(0)/Th)
        nec=n0cold*exp(-phi(0)/Tc)
        b(0)=-2.d0/dxt(1)**2-neh/Th-nec/Tc
        c(0)=2.d0/dxt(1)**2
        f(0)=ni(0)-neh*(1.d0+phi(0)/Th)-nec*(1.d0+phi(0)/Tc)
        
        do i=1,ncell-1
           neh=n0hot*exp(-phi(i)/Th)
           nec=n0cold*exp(-phi(i)/Tc)
           a(i)=2.d0/dxt(i)/(dxt(i)+dxt(i+1))
           b(i)=-2.d0/(dxt(i)*dxt(i+1))-neh/Th-nec/Tc
           c(i)=2.d0/dxt(i+1)/(dxt(i)+dxt(i+1))
           f(i)=ni(i)-neh*(1.d0+phi(i)/Th)-nec*(1.d0+phi(i)/Tc)
        enddo


        neh=n0hot*exp(-phi(ncell)/Th)
        nec=n0cold*exp(-phi(ncell)/Tc)
        neold=neh+nec
        peold=neh*Th+nec*Tc
        a(ncell)=2.d0/dxt(ncell)**2
        b(ncell)=-a(ncell)-sqrt(2.d0/peold)*neold/dxt(ncell) -neh/Th-nec/Tc
        f(ncell)=ni(ncell)-neh*(1.d0+phi(ncell)/Th)-nec*(1.d0+phi(ncell)/Tc)&
                    -sqrt(8.d0*peold)/dxt(ncell) *(1.d0+0.5d0*neold*phi(ncell)/peold)


!*    2.2.2 - inversion de la matrice tridiagonale

        call gauss(nmax,ncell,a,b,c,f,bx,fx,phi)


!*     2.2.3 - calcul de la densite electronique dans le plasma
!
    do i=0,ncell
       nhot(i)=n0hot*exp(-phi(i)/Th)
         ncold(i)=n0cold*exp(-phi(i)/Tc)
       ne(i)=nhot(i)+ncold(i)
       rho(i)=ni(i)-ne(i)
    enddo

!    *    2.2.4 - calcul de la pression electronique
!    *          et des gradients de densite
!    *          electronique et ionique au bord
!
        phot(ncell)=nhot(ncell)*Th
        pcold(ncell)=ncold(ncell)*Tc
        pe(ncell)=phot(ncell)+pcold(ncell)
        grade=(log(ne(ncell))-log(ne(ncell-1)))/(xt(ncell)-xt(ncell-1))
        gradi=(log(ni(ncell))-log(ni(ncell-1)))/(xt(ncell)-xt(ncell-1))


!    *     2.2.5 calcul de la densite electronique dans la gaine vide d'ions

     kvide=sqrt(n0hot/2.d0/Th)
     uphi=0.d0
     
     do i=ncell+1,ntotal
        if(i.eq.(ncell+1))then
           dxt(ncell+1)=0.
        else
           dxt(i)=0.0250*sqrt(Th/nhot(i-1))
        endif
        xt(i)=xt(i-1)+dxt(i)
        uphi=uphi+kvide*sqrt(1.d0+pcold(i-1)/phot(i-1))*dxt(i)
        phi(i)=phi(ncell)+2.d0*Th*log(1.d0+uphi*exp(-0.5d0*phi(ncell)/Th))

        nhot(i)=n0hot*exp(-phi(i)/Th)
        ncold(i)=n0cold*exp(-phi(i)/Tc)
        ne(i)=nhot(i)+ncold(i)
        rho(i)=-ne(i)
        phot(i)=nhot(i)*Th
        pcold(i)=ncold(i)*Tc
        pe(i)=phot(i)+pcold(i)
        E(i)=sqrt(2.d0*pe(i))
     enddo

!*     2.2.6 calcul du nombre total d'electrons et d'ions

    nti=0.d0
    do i=1,ncell
       nti=nti+ni1s2(i)*dxt(i)
    enddo

    nthot=0.d0
    ntcold=0.d0
    do i=1,ntotal
       nthot=nthot+0.5d0*(nhot(i-1)+nhot(i))*dxt(i)
       ntcold=ntcold+0.5d0*(ncold(i-1)+ncold(i))*dxt(i)
    enddo
    nthot=nthot+E(ntotal)
    nte=nthot+ntcold

    if(itime.eq.1) En_hot0=nthot*(e0/Tn0)*Th

    En_cold=ntcold*0.5d0*Tc


!*     2.2.7 ajustement de n0hot pour conserver le nombre
!*           total d'electrons chauds (alors le nombre d'electrons
!*           froids est automatiquement conserve, car le potentiel
!*           en 0 s'ajuste en consequence)

    if(nb_cons)then
         if(itime.eq.1)then
            nthot0=nthot
         else
            if(iphi.gt.1) n0hot=n0hot*(nthot0/nthot)
         endif
    endif
      
    if(En_cons.and.itime.eq.1)then
       En_cold0=En_cold
       write(*,*)
       write(*,*)'En_hot0=', En_hot0
       write(*,*)'En_cold0=', En_cold0
       write(*,*)
    endif


!*     2.2.7 calcul de la vitesse d'interface des cellules vides d'ions

      if(itime.gt.1)then
         do i=ncell+1,ntotal
            vint(i)=(xt(i)-xtold(i))/dt
         enddo
      endif

!*     2.2.8 calcul des gradients de densite electronique

      do i=1,ntotal-1
         gradnh(i)=(nhot(i+1)-nhot(i-1))/(dxt(i)+dxt(i+1))
         gradnc(i)=(ncold(i+1)-ncold(i-1))/(dxt(i)+dxt(i+1))
      enddo

     gradnh(ncell)=gradnh(ncell-1)*nhot(ncell)/nhot(ncell-1)
     gradnh(ntotal)=gradnh(ntotal-1)*nhot(ntotal)/nhot(ntotal-1)
     gradnh(ncell+1)=gradnh(ncell)
     
     gradnc(ncell)=gradnc(ncell-1)
     gradnc(ntotal)=gradnc(ntotal-1)
     if(n0cold.gt.1.e-04) then
       if(ncold(ncell-1).gt.1.d-30)  gradnc(ncell)=gradnc(ncell-1)*ncold(ncell)/ncold(ncell-1)
       if(ncold(ntotal-1).gt.1.d-30) gradnc(ntotal)=gradnc(ntotal-1)*ncold(ntotal)/ncold(ntotal-1)
     endif
     gradnc(ncell+1)=gradnc(ncell)


!*     2.2.9 calcul de l'energie fournie par les electrons chauds [et
!*           reajustement de Th (ancienne methode)]

      if(itime.gt.1.and.iphi.gt.1)then
         dWhot(0)=0.5d0*(phiold(0)+phi(0))*(nhot(0)-nhotold(0)-vint(0)*dt&
            *0.5d0*(gradnh(0)+ghold(0)))
         Whot1=Whot1old+0.25d0*dWhot(0)*(dxtold(1)+dxt(1))
         SWhot(0)=0.25d0*dWhot(0)*(dxtold(1)+dxt(1))
         do i=1,ncell
            dWhot(i)=0.5d0*(phiold(i)+phi(i))*(nhot(i)-nhotold(i)&
                -vint(i)*dt*0.5d0*(gradnh(i)+ghold(i)))
            Whot1=Whot1+0.25d0*dWhot(i)*(dxtold(i)+dxt(i)+dxtold(i+1)+dxt(i+1))
            SWhot(i)=SWhot(i-1)+0.25d0*dWhot(i)*(dxtold(i)+dxt(i)+dxtold(i+1)+dxt(i+1))
         enddo
         Whot2=Whot2old
         do i=ncell+1,ntotal-1
            dWhot(i)=0.5d0*(phiold(i)+phi(i)) *(nhot(i)-nhotold(i)&
                -vint(i)*dt*0.5d0*(gradnh(i)+ghold(i)))
            Whot2=Whot2+0.25d0*dWhot(i)*(dxtold(i)+dxt(i)+dxtold(i+1)+dxt(i+1))
            SWhot(i)=SWhot(i-1)+0.25d0*dWhot(i)*(dxtold(i)+dxt(i)+dxtold(i+1)+dxt(i+1))
         enddo
         dWhot(ntotal)=0.5d0*(phiold(ntotal)+phi(ntotal))&
                *(nhot(ntotal)-nhotold(ntotal)-vint(ntotal)&
                *dt*0.5d0*(gradnh(ntotal)+ghold(ntotal)))
         Whot2=Whot2+0.25d0*dWhot(ntotal) *(dxtold(ntotal)+dxt(ntotal))
         SWhot(ntotal)=SWhot(ntotal-1)+0.25d0*dWhot(ntotal)*(dxtold(ntotal)+dxt(ntotal))
         Whot=Whot1+Whot2
       endif



!    *     2.2.10 calcul de l'energie fournie par les electrons froids et
!    *           reajustement de Tc
!
          if(itime.gt.1.and.iphi.gt.1)then
             Wcold=Wcoldold+0.125d0*(phiold(0)+phi(0))&
                    *(ncold(0)-ncoldold(0)-vint(0)*dt&
                    *0.5d0*(gradnc(0)+gcold(0)))*(dxtold(1)+dxt(1))
             do i=1,ntotal-1
                Wcold=Wcold+0.125d0*(phiold(i)+phi(i))&
                        *(ncold(i)-ncoldold(i)&
                        -vint(i)*dt*0.5d0*(gradnc(i)+gcold(i)))&
                        *(dxtold(i)+dxt(i)+dxtold(i+1)+dxt(i+1))
             enddo
             Wcold=Wcold+0.125d0*(phiold(ntotal)+phi(ntotal))&
                    *(ncold(ntotal)-ncoldold(ntotal)-vint(ntotal)&
                    *dt*0.5d0*(gradnc(ntotal)+gcold(ntotal)))&
                    *(dxtold(ntotal)+dxt(ntotal))
             if(En_cons.and.nb_cons)then
                if(iphi.ne.iter)then
                   Tc=(3.d0*Tc+2.d0*(En_cold0-Wcold)/ntcold)/4.d0
                else
                   Tc=(1.d0*Tc+2.d0*(En_cold0-Wcold)/ntcold)/2.d0
                endif
             endif
          endif


!        *     2.2.11 calcul du champ electrique dans toute la detente

            do i = 1,ncell
               E1s2(i)=(phi(i)-phi(i-1))/dxt(i)
            end do
                
            do i = 1,ncell-1
               E(i)=(dxt(i+1)*E1s2(i)+dxt(i)*E1s2(i+1))/(dxt(i)+dxt(i+1))
            end do
                
             E(ncell)=sqrt(2.d0*pe(ncell))

!            do i = 1,ncell
!               if(xttest(i).ge.xt(itest(i)))then
!                 do j=itest(i),ntotal-1
!                   if(xttest(i).le.xt(j+1))then
!                     itest(i)=j
!                     goto 301
!                   endif
!                 enddo
!                 itest(i)=ntotal-1
!        301      continue
!               else
!                 do j=itest(i)-1,0,-1
!                   if(xttest(i).ge.xt(j))then
!                     itest(i)=j
!                     goto 302
!                   endif
!                 enddo
!                 itest(i)=0
!        302      continue
!                 endif

!*     2.2.12 ajustement de la vitesse aux temps 'entiers'
    
    if(itime.gt.1) then
       do i = 1,ncell
          v(i)=vint(i)+dt*(3.d0*E(i)+Eold(i))*charge(i)/8.d0
       end do
    endif

!*     2.2.13 calcul de l'energie cinetique des ions

    En_ion=0.
    do i = 1,ncell-1
       En_ion=En_ion+qiSS(i)*v(i)**2/2.d0/charge(i)
    end do
    if(profil.eq.'step') En_ion = En_ion+qiSS(ncell)*v(ncell)**2/4.d0/charge(i)
    if(profil.ne.'step') En_ion = En_ion+qiSS(ncell)*v(ncell)**2/2.d0/charge(i)



!*     2.2.14 calcul de l'energie electrostatique

    En_elec=0.
    do i = 1,ntotal-1
       En_elec=En_elec+0.25d0*(E(i)**2)*(dxt(i)+dxt(i+1))
    end do
    En_elec=En_elec+0.25d0*(E(ntotal)**2)*dxt(ntotal)
    En_elec=En_elec+E(ntotal)*Th
            
!*     2.2.15 calcul de l'energie totale

    if(itime.eq.1)then
       En_totale=En_ion+En_elec+0.5d0*ntcold*Tc+En_hot0
    endif

!*    2.2.16 reajustement de Th
!*           (remplace l'ajustement precedent)

      if(En_cons.and.itime.gt.1.and.iphi.gt.1)then

         enew=(En_totale-En_ion-En_elec-0.5d0*ntcold*Tc)*Tn0/nthot/Thmax
         Thnew=2.*Thmax*enew/Tn0

         if(iphi.ne.iter)then
            Th=(iter2*Th+Thnew)/(iter2+1)
         else
            Th=(iter3*Th+Thnew)/(iter3+1)
         endif
    endif
    
10    continue


!*         2.3 champs 'theoriques'
!
!*    2.3.1 normalisation au champ theorique du modele self-similaire

     if(itime.eq.1)then
        Enorm=0.d0
     else
        Ess=1.d0*sqrt(Th)/time
        Enorm=E(ncell)/Ess
     endif

!*    2.3.2 comparaison au champ 'theorique' suppose 'fite' le
!*          champ au bord a tout instant

     Ebord0=sqrt(2.d0*n0hot)/exp(0.5d0)
     Ebordth=2.d0*Ebord0*sqrt(Th)/sqrt(4.d0+(Ebord0*time)**2)


!*         2.4 test d'arret sur le nombre d'iterations

!        if(itmax.eq.1) goto 101


!*         2.5 sorties de fonctions dependant du temps

        vmax=0.d0
        ivmax=ncell
        do i=1,ncell
           if(v(i).gt.vmax) then
             vmax=v(i)
             ivmax=i
           endif
        enddo
        vfinal=v(ivmax)+E(ivmax)*charge(ivmax)*time


        lDebye=sqrt(Th/ne(ncell))
        lgrade=-1./grade
        if(itime.eq.1)then
           lgradi=0.
        else
           lgradi=-1./gradi
        endif

        nstep=(tmax/dt)
        nsort=1
        if(nstep.gt.2000)nsort=nstep/2000

        if(itime-1.ne.((itime-1)/nsort)*nsort.and..not.laststep) go to 102

102    continue

!*         2.6 test d'arret sur le temps (ici s'arrete normalement
!*          un calcul standard avec itmax.gt.1 et tmax.gt.0 apres
!*          un nombre fini d'iterations)
    
        if(time.ge.(tmax-1.d-5)) goto 101
        if(itime.eq.itmax) goto 101


!*         2.7 incrementation du temps
            
            dtold=dt
            dt=dti
            if((time+dt).gt.(tmax-1.d-5)) then
               dt=tmax-time
               laststep=.true.
            endif
            time=time+dt
    
!*         2.8 modification de la vitesse aux temps intermediaires
!*             'demi-entiers'
    
        if(itime.eq.1) then
           do i = 1,ncell
              vint(i)=v(i)+0.5d0*dt*E(i)*charge(i)
           end do
           

!*            2.8.1 - construction des tableaux a,b,c, et f pour
!*              le calcul implicite de la vitesse avec viscosite

           delt=0.5*(dtold+dt)
           b(0)=1.d0/delt
           c(0)=0.d0
           f(0)=0.d0
        
           do i=1,ncell-1
              a(i)=-2.d0*nu/dxt(i)/(dxt(i)+dxt(i+1))
              b(i)=1.d0/delt+2.d0*nu/(dxt(i)*dxt(i+1))
              c(i)=-2.d0*nu/dxt(i+1)/(dxt(i)+dxt(i+1))
              f(i)=E(i)*charge(i)+vint(i)/delt
           enddo
    
           a(ncell)=0.d0
           b(ncell)=1.d0/delt
           f(ncell)=E(ncell)*charge(ncell)+vint(ncell)/delt
     
!*          2.8.2 - inversion de la matrice tridiagonale

           call gauss(nmax,ncell,a,b,c,f,bx,fx,vint)
    
      endif


!*         2.9 modification de la position
    
    do i = 1,ncell
       xt(i)=xt(i)+dt*vint(i)
           if(xt(i).lt.x0(0))then
              xt(i)=2.d0*x0(0)-xt(i)
              vint(i)=-vint(i)
           endif
    end do

        

!*         2.10 rearrangement des numeros des ions

   
   do j=2,ncell
      xxt=xt(j)
      xx0=x0(j)
      xxtold=xtold(j)
      vv=v(j)
      vvint=vint(j)
      iidebut=idebut(j)
      qqiSS=qiSS(j)
      nnhot=nhot(j)
      nncold=ncold(j)
      pphi=phi(j)
      EE=E(j)
      ggradnh=gradnh(j)
      ggradnc=gradnc(j)
      ddxt=dxt(j)
         ccharge=charge(j)
      do i=j-1,1,-1
         if(xt(i).le.xxt) goto 95
         xt(i+1)=xt(i)
         x0(i+1)=x0(i)
         xtold(i+1)=xtold(i)
         v(i+1)=v(i)
         vint(i+1)=vint(i)
         idebut(i+1)=idebut(i)
       qiSS(i+1)=qiSS(i)
       nhot(i+1)=nhot(i)
       ncold(i+1)=ncold(i)
       phi(i+1)=phi(i)
       E(i+1)=E(i)
       gradnh(i+1)=gradnh(i)
       gradnc(i+1)=gradnc(i)
       dxt(i+1)=dxt(i)
             charge(i+1)=charge(i)
      enddo
      i=0
95    xt(i+1)=xxt
      x0(i+1)=xx0
      xtold(i+1)=xxtold
      v(i+1)=vv
      vint(i+1)=vvint
      idebut(i+1)=iidebut
      qiSS(i+1)=qqiSS
      nhot(i+1)=nnhot
      ncold(i+1)=nncold
      phi(i+1)=pphi
      E(i+1)=EE
      gradnh(i+1)=ggradnh
      gradnc(i+1)=ggradnc
      dxt(i+1)=ddxt
         charge(i+1)=ccharge
   enddo
   
   do j=1,ncell
      irang(idebut(j))=j
   enddo



100   continue
101    continue


    write(*,*) 'OK step 2'



!*               3 - calcul de la densite theorique (modele
!*            self-similaire)
    

      if(itime.eq.1)then
         do i=ncell+1,ntotal
            x0(i)=xt(i)
         enddo
      endif
    
    if(itmax.eq.1.or.time.le.1.d-04) goto 201

    do i=0,ntotal
       xi=xt(i)/sqrt(Th)/time
       if(xi.lt.-1.d0) then
          nss(i)=n0hot
       else
          nss(i)=n0hot*exp(-(xi+1.d0))
       endif
    enddo
    
    do i=0,ntotal
       difth(i)=(ni(i)-nss(i))/nss(i)
    enddo

201    continue

    write(*,*) 'OK step 3'

    write(*,*)
    write(*,*) time
    write(*,*)
    stop

end program Ionboost
