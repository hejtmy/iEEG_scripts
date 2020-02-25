classdef CHHeader < matlab.mixin.Copyable %je mozne kopirovat pomoci E.copy();
    %CHHEADER Trida na praci s headerem od Jirky Hammera
    %Kamil Vlcek, FGU AVCR, since 2016 04
    
    properties (Access = public)
        H; %data od Jirky Hammera
        %E; % unikatni jmena elektrod, napr RG, I, GC ...
        chgroups; %cell array, kazda bunka jsou cisla kanalu ve skupine
        els;
        RjCh;
        BrainAtlas_zkratky; %tabulka od Martina Tomaska
        filterMatrix; %kopie filterMatrix, vytvari se pri zmene reference
        sortorder; %index serazenych kanalu
        sortedby; %podle ceho jsou kanaly serazeny
        plotCh2D; %udaje o 2D grafu kanalu ChannelPlot2D, hlavne handle
        channelPlot@ChannelPlot;    % handle na ChannelPlot
        reference; %aby trida vedela, jestli je bipolarni nebo ne        
        classname; %trida v ktere je Header vytvoren
        brainlabels; %struct array, obsahuje ruzna vlastni olabelovani kanalu
        hull; %data for convex hull
    end
    %#ok<*PROPLC>
    
    events
        FilterChanged
    end
    
    methods (Access = public)
        function obj = CHHeader(H,filename,reference,classname)
            %konstruktor
            %filename se zatim na nic nepouziva
            obj.H = H;     
            if exist('filename','var') && ~isempty(filename)
               obj.H.filename = filename;
            end
              %nefunguje protoze name je napriklad RG12 a ne jen RG, takze neni unikatni pro kazdou elektrodu
%             E = cell(size(H.electrodes,2),1); %#ok<*PROP>
%             for iE= 1:size(H.electrodes,2)
%                 E{iE}=H.electrodes(iE).name;
%             end
%             [U,idx]=unique(cell2mat(E)); 
%             obj.E = cell(numel(U),1);
%             for iE = 1:numel(idx)
%                 obj.E{iE}= E{idx};
%             end
             obj = obj.SelChannels(); 
             obj.sortorder = 1:numel(obj.H.channels); %defaultni sort order
             obj.sortedby = '';
             if exist('reference','var'), obj.reference = reference; else, obj.reference = []; end
             if exist('classname','var'), obj.classname = classname; else, obj.classname = []; end
             obj.ChannelPlot2DInit(); %some fields we need also in ChannelPlot
        end
        function delete(obj) %destructor of a handle class
            if isfield(obj.plotCh2D,'fh') && ~isempty(obj.plotCh2D.fh) && ishandle(obj.plotCh2D.fh) ,close(obj.plotCh2D.fh); end
        end
        function [obj, chgroups, els] = ChannelGroups(obj,chnsel,subjname,forcechgroups)
            %vraci skupiny kanalu (cisla vsech channels na elekrode) + cisla nejvyssiho kanalu v na kazde elektrode v poli els
            % subjname - jestli jsou skupiny podle subjname (napr p173, u CHibertMulti) nebo elektrod (napr A)  
            if ~exist('subjname','var') || isempty(subjname), subjname = iff( strcmp(obj.classname,'CHilbertMulti')); end %defaultne podle classname, pokud neni CHilbertMulti, pouzivaji se jmena elektrod
            if ~exist('chnsel','var') || isempty(chnsel) %pokud nenam zadny vyber kanalu, pouziva se pri load dat
            if ~exist('forcechgroups','var') || isempty(forcechgroups), forcechgroups = 0; end %chci prepocitat chgroups 
                if isempty(obj.chgroups) || forcechgroups               
                    chgroups = obj.getChannelGroups(subjname); %pouziju vlastni funkci, getChannelGroups_kisarg je hrozne pomale
                    els = zeros(1,numel(chgroups)); 
                    for j = 1:numel(chgroups)
                        els(j)=max(chgroups{j});
                    end
                    els = sort(els);
                    obj.chgroups = chgroups; 
                    obj.els = els;
                else
                    chgroups = obj.chgroups; 
                    els = obj.els;
                end
            else %pokud mam definovan vyber kanalu v chsel. Pouzivam z grafu ChannelPlot
                if obj.channelPlot.plotCh3D.allpoints %pokud chci zobrazovat i ostatni kanal jako tecky
                   allchns = setdiff(setdiff(obj.H.selCh_H,chnsel),obj.RjCh); %in the second group are all other channels, exluding rejected channels
                   chgroups = {chnsel,allchns}; %do druhe skupiny dam ostatni kanaly
                elseif subjname
                   chgroups = obj.getChannelGroups(subjname,chnsel);  
                else
                   chgroups = {chnsel}; %pokud mam vyber kanalu, zatim to nechci resit a vsechny v jedne skupine - bez ohledu na elektrody, jako cellarray
                end
                els = obj.els;
            end
        end
        function [obj,els2plot,triggerCH ] = ElsForPlot(obj)
            %vrati cisla nejvyssiho kanalu pro zobrazeni - kdyz je nejaka elektroda moc dlouha, tak ji rozdeli
            els2plot = zeros(1,numel(obj.els));
            e0 = 0; %cislo elektrody z minuleho cyklu
            iEls =  1; %index v els2plot;
            kontaktumax = 15;
            for e = 1:numel(obj.els)
                while obj.els(e)-e0 > kontaktumax %pokud je nejaka elektroda moc dlouha, rozdelim ji do zobrazeni po padesati kouscich
                    els2plot(iEls) = e0 + kontaktumax;
                    e0 = e0+kontaktumax;
                    iEls = iEls+1;
                    if e==numel(obj.els)
                        els2plot = [els2plot, obj.els(e)]; %#ok<AGROW> %11.7.2019 - pokud jsem uz u posledni elektrody, musi jeste pridat zvyvajici kontakty 
                    end
                end
                if obj.els(e)-e0 > 3 %pokud je elektroda prilis kratka, nebudu ji zobrazovat samostatne
                    els2plot(iEls) = obj.els(e);
                    e0= obj.els(e);
                    iEls = iEls+1;
                end
            end 
            els2plot(els2plot==0)=[];
            triggerCH = obj.H.triggerCH;
        end
        function obj = RejectChannels(obj,RjCh)
            %ulozi cisla vyrazenych kanalu - kvuli pocitani bipolarni reference 
            obj.RjCh = RjCh;            
        end
        function chs = GetChOK(obj)
            %vraci cisla kanalu, ktera jsou SEEG a nejsou vyrazena
            chs = setdiff(obj.H.selCh_H,obj.RjCh);
        end
        function chs = ChannelsN(obj)
            %vraci celkovy pocet kanalu
            chs = length(obj.H.channels);
        end
        function [ch,name,MNI,brainAtlas] = ChannelNameFind(obj,name)
            % najde kanal podle jmena kontaktu, napr 'R5', name musi byt na zacatku jmena, 
            % ale nemusi byt cele
            % vraci jeho cislo, cele jmeno, mni souradnice a pojmenovani podle brain atlasu 
            MNI = [];
            brainAtlas = '';
            for ch = 1:size(obj.H.channels,2)
                if 1==strfind(obj.H.channels(1,ch).name,name)
                    if isfield(obj.H.channels,'MNI_x') %pokud mni souradnice existuji
                        MNI = [obj.H.channels(ch).MNI_x obj.H.channels(ch).MNI_y obj.H.channels(ch).MNI_z];
                    end
                    if isfield(obj.H.channels,'ass_brainAtlas')
                        brainAtlas = obj.H.channels(ch).ass_brainAtlas;
                    end
                    name = obj.H.channels(1,ch).name;
                    return;
                end
            end
            ch = 0;
        end
        function [XYZ,cplot] = ChannelPlotProxy(obj,chnvals,chnsel,selch,roi,popis,rangeZ)
%             disp('Calling ChannelPlot through proxy');
            if isvalid(obj.channelPlot)
                [XYZ,cplot] = obj.channelPlot.ChannelPlot3D(chnvals,chnsel,selch,roi,popis,rangeZ);
            else
                obj.channelPlot = ChannelPlot(obj);
                [XYZ,cplot] = obj.channelPlot.ChannelPlot3D(chnvals,chnsel,selch,roi,popis,rangeZ);
            end
        end
        function obj = ChannelPlot2DInit(obj)
            %is called already in CHHeader Constructor
            if ~isfield(obj.plotCh2D,'chseltop'), obj.plotCh2D.chseltop = 1; end %jestli se ma vybrany kanal zobrazovat na popredi ostatnych  - zlute kolecko
            if ~isfield(obj.plotCh2D,'names'), obj.plotCh2D.names = 1; end %jestli se maji vypisovat jmena kanalu
            if ~isfield(obj.plotCh2D,'lines'), obj.plotCh2D.lines=1; end %defaltne se kresli cary mezi kanaly jedne elektrody
            if ~isfield(obj.plotCh2D,'transparent'), obj.plotCh2D.transparent=0; end %defaltne se kresli body nepruhledne
            if ~isfield(obj.plotCh2D,'chshow'), obj.plotCh2D.chshow = 1:numel(obj.H.channels); end %channels to be shown, i.e. not filtered out by obj.FilterChannels
            if ~isfield(obj.plotCh2D,'ch_displayed'), obj.plotCh2D.ch_displayed=obj.plotCh2D.chshow; end %really diplayed channels, by FilterChannels and by marks fghjkl
            if ~isfield(obj.plotCh2D,'chshowstr'), obj.plotCh2D.chshowstr = ''; end   %defaultne bez filtrovani
            if ~isfield(obj.plotCh2D,'coronalview'), obj.plotCh2D.coronalview = 0; end   %defaultne vlevo axial view           
            if ~isfield(obj.plotCh2D,'color_index'), obj.plotCh2D.color_index = 1; end   %index of the first color in             
            if ~isfield(obj.plotCh2D,'color_def') %definice barev dynamicky, aby se daly upravovat
                obj.plotCh2D.color_def = [ [0 1 0]; [0 0 1]; [1 0 0]; [ 0 1 1]; [1 0 1]; [ 0 0 0 ]];     %default colors 'gbrcmk'                    
            end   
            if ~isfield(obj.plotCh2D,'color_order'), obj.plotCh2D.color_order = 1:6; end   %defaultne order of the colors   
            if ~isfield(obj.plotCh2D,'marks')  %handle na funkci z CiEEGData @obj.PlotResponseCh
                obj.plotCh2D.marks = [1 1 1 1 1 1]; %ktere znacky fghjjkl se maji zobrazovat
            end
            if ~isfield(obj.plotCh2D,'chsel'), obj.plotCh2D.chsel = 1;  end %one selected channel markad by red point
            if ~isfield(obj.plotCh2D,'label'), obj.plotCh2D.label = ''; end        
        end
        function ChannelPlot2D(obj,chsel,plotRCh,plotChH,label)
            %vstupni promenne
            %plotRCh - cela struktura plotRCh z CiEEGData
            if ~exist('chsel','var') %promenna na jeden cerveny kanal
                chsel = obj.plotCh2D.chsel;                
            else
                obj.plotCh2D.chsel = chsel;
            end
            chselo = obj.sortorder(chsel); %jeden kanal, ktery je zobrazeny v PlotResponseCh
                                           %chsel je index v sortorder, chselo je skutecne cislo kanalu
            if ~exist('plotRCh','var') 
                if isfield(obj.plotCh2D,'selCh') %promenna na vic oznacenych kanalu f-l, podle obj.PlotRCh.SelCh
                    selCh = obj.plotCh2D.selCh;
                else
                    selCh = [];                     
                end
                if isfield(obj.plotCh2D,'selChNames') %pojmenovani vyberu kanalu pomoci f-l
                    selChNames = obj.plotCh2D.selChNames;
                else
                    selChNames = cell(1,6);                    
                end  
                obj.SetSelCh(selCh,selChNames,1);
            else
                if isfield(plotRCh,'selCh'), selCh = plotRCh.selCh; else, selCh = []; end
                if isfield(plotRCh,'selChNames'), selChNames = plotRCh.selChNames; else, selChNames = cell(1,6);end                
                obj.SetSelCh(selCh,selChNames); 
            end
            
            if exist('plotChH','var')  %handle na funkci z CiEEGData @obj.PlotResponseCh
                obj.plotCh2D.plotChH = plotChH;
            end
            
            if ~exist('label','var') %promenna z CM oznacujici nejaky label celeho souboru 
                label = obj.plotCh2D.label;
            else
                obj.plotCh2D.label = label;
            end
           
            %------------------------- vytvoreni figure -----------------------------------
            x = [obj.H.channels(:).MNI_x];
            y = [obj.H.channels(:).MNI_y];
            z = [obj.H.channels(:).MNI_z];                
            
            load('GMSurfaceMesh.mat'); %seda hmota v MNI
            if isfield(obj.plotCh2D,'boundary') && obj.plotCh2D.boundary && ~isfield(obj.plotCh2D,'BrainBoundaryXY') %trva docela dlouho nez se to spocita
                obj.plotCh2D.BrainBoundaryXY = boundary(GMSurfaceMesh.node(:,1),GMSurfaceMesh.node(:,2)); %vnejsi hranice mozku
                obj.plotCh2D.BrainBoundaryYZ = boundary(GMSurfaceMesh.node(:,2),GMSurfaceMesh.node(:,3));
                obj.plotCh2D.BrainBoundaryXZ = boundary(GMSurfaceMesh.node(:,1),GMSurfaceMesh.node(:,3)); %coronal view
            end
            
            size_ch = 12; %velikosti krouzko oznacujicich kanaly
            size_selCh = 50; %7;
            x_text = -100;
            if isfield(obj.plotCh2D,'fh') && ishandle(obj.plotCh2D.fh)
                figure(obj.plotCh2D.fh); %pouziju uz vytvoreny graf
                clf(obj.plotCh2D.fh); %graf vycistim
            else
                obj.plotCh2D.fh = figure('Name',['ChannelPlot2D - ' label]);                     
            end            
                   
            if isfield(obj.plotCh2D,'chshow') && numel(obj.plotCh2D.chshow) < numel(obj.H.channels) %pokud chci zobrazovat jen cast kanalu podle chshow
                els = obj.plotCh2D.chshow;
                els0 = obj.plotCh2D.chshow; %nebudu resit zacatky a konec elektrod
                chshow = obj.plotCh2D.chshow;
            else
                els = obj.els; %konce elektrod/pacientu u CM
                els0 = [1 obj.els(1:end-1)+1]; %zacatky elektrod/pacientu u CM
                chshow = 1:numel(obj.H.channels); 
            end
            
            subplot(1,2,1);                      
            barvy = [obj.plotCh2D.color_def(obj.plotCh2D.color_index:end,:); obj.plotCh2D.color_def(1:obj.plotCh2D.color_index-1,:)]; %barvy od poradi colorindexu
            % ----------------- axial/coronal plot   ---------------------------   
            xyz = iff(obj.plotCh2D.coronalview, [1 3], [1 2]); %jesti zobrazovat MNI souradnice xy (=axial) nebo xz (=coronal)
            MNIxyz = vertcat(x,y,z); %abych mohl pouzivat souradnice xyz dynamicky podle coronalview
            Yaxislabel = iff(obj.plotCh2D.coronalview, 'MNI Z', 'MNI Y'); 
            if isfield(obj.plotCh2D,'boundary') && obj.plotCh2D.boundary
                %defaultne budu vykreslovat scatter, ale kvuli kopirovani se bude hodit i jen boundary
                BrainBoundary = iff(obj.plotCh2D.coronalview,obj.plotCh2D.BrainBoundaryXZ,obj.plotCh2D.BrainBoundaryXY); 
                plot(GMSurfaceMesh.node(BrainBoundary,xyz(1)),GMSurfaceMesh.node(BrainBoundary,xyz(2)));
            else
                %scatter celeho mozku
                scatter(GMSurfaceMesh.node(:,xyz(1)),GMSurfaceMesh.node(:,xyz(2)),'.','MarkerEdgeAlpha',.1); %seda hmota normalizovaneho mozku
            end           
            hold on;             
            
            if obj.plotCh2D.lines >= 0 %-1 means not to show channels not marked by fghjkl, cili tady se nekresli nic                
                plotstyle = iff(obj.plotCh2D.lines,'-o','o'); %,'ok' pro cernobile
                if numel(els) == numel(chshow) %if no electrode ends are distinguished
                    plot(MNIxyz(xyz(1),chshow),MNIxyz(xyz(2),chshow),plotstyle); %plot kontaktu jedne elektrody
                else
                    for ie = 1:numel(els)
                        plot(MNIxyz(xyz(1),els0(ie):els(ie)),MNIxyz(xyz(2),els0(ie):els(ie)),plotstyle); %plot kontaktu jedne elektrody
                    end                        
                end
            end 
            
            if ~isempty(chsel) %pokud je vybrany nejaky kanal - zobrazit jako zlute kolecko
                if obj.plotCh2D.chseltop > 0 %pokud 0 , nechci ho vybrany kanal vubec vubec zobrazit
                    h_selection = plot(x(chselo),y(chselo),'o','MarkerSize',size_ch,'MarkerEdgeColor','y','MarkerFaceColor','y'); 
                end
                chstr = iff(isempty(obj.sortedby),num2str(chsel), [ num2str(obj.sortorder(chsel)) '(' obj.sortedby  num2str(chsel) ')' ]);
                title( [ 'channel ' chstr ]);
                
            end
            if ~isempty(selCh) %vybery kanalu fghjkl                
                ch_displayed = cell(1,6);
                for ci = 1:numel(obj.plotCh2D.color_order) %1:size(selCh,2) %jednu znacku za druhou m = size(selCh,2):-1:1 
                   m = obj.plotCh2D.color_order(ci);
                   if  obj.plotCh2D.marks(m) %pokud se ma znacka zobrazovat
                       ch = find(selCh(:,m)); %seznam cisel vybranych kanalu pro danou znacku
                       ch = intersect(chshow,ch); 
                       %plot(x(ch),y(ch),'o','MarkerSize',size_selCh,'MarkerEdgeColor',barvy(m),'MarkerFaceColor',barvy(m));
                       sh = scatter(MNIxyz(xyz(1),ch),MNIxyz(xyz(2),ch),size_selCh,barvy(m,:),'filled');
                       if obj.plotCh2D.transparent, alpha(sh,.5); end %volitelne pridani pruhlednosti
                       ch_displayed{m} = ch';
                   end
                end
                if obj.plotCh2D.lines < 0 %if not all channels are displayed, but only these with marks fghjkl
                    obj.plotCh2D.ch_displayed = unique(cell2mat(ch_displayed))'; %ktere kanaly jsou opravu zobrazeny, do radku
                else
                    obj.plotCh2D.ch_displayed = chshow; %if all channels are shown (according to FilterChannels)
                end
            end            
            if obj.plotCh2D.names == 1
                chnnames = num2cell(obj.plotCh2D.ch_displayed); %channel no                                
            elseif obj.plotCh2D.names == 2
                chnnames = {obj.H.channels(obj.plotCh2D.ch_displayed).name}; %channel name
            else
                chnnames = {obj.H.channels(obj.plotCh2D.ch_displayed).neurologyLabel}; %neurology label
            end 
            
            if obj.plotCh2D.names > 0 %if to plot channel labels                               
               text(MNIxyz(xyz(1),obj.plotCh2D.ch_displayed),MNIxyz(xyz(2),obj.plotCh2D.ch_displayed),chnnames,'FontSize', 8);
            end                              

            if obj.plotCh2D.chseltop>1, uistack(h_selection, 'top'); end %the one selected channel topmost
            text(-70,70,'LEVA');
            text(55,70,'PRAVA');  
            axis equal;  
            if isfield(obj.plotCh2D,'grid') && obj.plotCh2D.grid==1
                grid on;
            end
                
            set(gca, 'XTick',-70:10:70); %xticks(-70:10:70); %xtics jsou az od 2016b
            set(gca, 'YTick',-100:10:70); %yticks(-100:10:70); %ytics jsou az od 2016b
            xlabel('MNI X'); %levoprava souradnice
            ylabel(Yaxislabel); %predozadni/hodnodolni souradnice
            if isfield(obj.plotCh2D,'background') && obj.plotCh2D.background==0
                set(gca,'color','none'); %zadne bile pozadi, pak ani v corelu
            end
           
            subplot(1,2,2);
            % ----------------- sagitalni plot ---------------------------
            if isfield(obj.plotCh2D,'boundary') && obj.plotCh2D.boundary
                plot(GMSurfaceMesh.node(obj.plotCh2D.BrainBoundaryYZ,2),GMSurfaceMesh.node(obj.plotCh2D.BrainBoundaryYZ,3));
            else
                scatter(GMSurfaceMesh.node(:,2),GMSurfaceMesh.node(:,3),'.','MarkerEdgeAlpha',.1);   %seda hmota normalizovaneho mozku
            end
            hold on;     
            
            plotstyle = iff(obj.plotCh2D.lines,'-o','o');
            if obj.plotCh2D.lines >= 0 %-1 znamena, ze se nemaji zobrazovat neoznacene kanaly pomoci fghjkl, cili tady se nekresli nic
                if numel(els) == numel(chshow) %if no electrode ends are distinguished
                    plot(y(chshow),z(chshow),plotstyle); %plot kontaktu jedne elektrody
                else
                    for ie = 1:numel(els)  
                        plot(y(els0(ie):els(ie)),z(els0(ie):els(ie)),plotstyle); %plot kontaktu jedne elektrody
                    end
                end
            end  
            if ~isempty(chsel) %pokud je vybrany nejaky kanal
                if obj.plotCh2D.chseltop > 0 %pokud 0 , nechci ho vybrany kanal vubec vubec zobrazit
                    h_selection = plot(y(chselo),z(chselo),'o','MarkerSize',size_ch,'MarkerEdgeColor','y','MarkerFaceColor','y'); 
                end
                
                text(x_text,110,[ obj.H.channels(1,chselo).name]);
                text(x_text,100,[ obj.H.channels(1,chselo).neurologyLabel ',' obj.H.channels(1,chselo).ass_brainAtlas]);
                if  isfield(obj.H.channels,'MNI_x') %vypisu MNI souradnice
                    text(x_text,90,[ 'MNI: ' num2str(round(obj.H.channels(1,chselo).MNI_x)) ', ' num2str(round(obj.H.channels(1,chselo).MNI_y )) ', ' num2str(round(obj.H.channels(1,chselo).MNI_z))]);
                else
                    text(x_text,90,'no MNI');
                end                
            end
            if ~isempty(selCh) %channel markings, channels x 6 marks 
                klavesy = 'fghjkl'; %abych mohl vypsat primo nazvy klaves vedle hvezdicky podle selCh
                for ci = 1:numel(obj.plotCh2D.color_order) %1:size(selCh,2) %:-1:1 %jednu znacku za druhou - naposled ty prvni aby byly nahore
                    m = obj.plotCh2D.color_order(ci);
                    if  obj.plotCh2D.marks(m) %pokud se ma znacka zobrazovat
                       ch = find(selCh(:,m)); %seznam cisel vybranych kanalu pro danou znacku
                       ch = intersect(chshow,ch); 
                       if ~isempty(ch) %pokud jsou takove nejake vybrane kanaly
                           %plot(y(ch),z(ch),'o','MarkerSize',size_selCh,'MarkerEdgeColor',barvy(m),'MarkerFaceColor',barvy(m));
                           sh = scatter(y(ch),z(ch),size_selCh,barvy(m,:),'filled');
                           if obj.plotCh2D.transparent, alpha(sh,.5); end %volitelne pridani pruhlednosti
                           
                           th = text(x_text+m*10,-90,klavesy(m), 'FontSize', 15,'Color',barvy(m,:)); %legenda k barvam kanalu dole pod mozkem
                           th.BackgroundColor = [.6 .6 .6];
                           if ~isempty(selChNames) && ~isempty(selChNames{m})
                             text(x_text+70,-60-m*7,cell2str(selChNames{m}), 'FontSize', 9,'Color',barvy(m,:)); %popisy znacek f-l                           
                           end
                       end
                    end
                    if exist('plotRCh','var') && isfield(plotRCh,'selChN') && ~isempty(plotRCh.selChN) && m==1  %cislo zobrazeneho vyberu kanalu, viz E.SetSelChActive
                        text(x_text+100,-60-m*7,['SelCh Active: ' num2str(plotRCh.selChN)], 'FontSize', 9);
                    end
                end
                if any(selCh(chselo,:),2)==1 %pokud je aktualni kanal jeden z vybranych                
                    klavesy = 'fghjkl'; %abych mohl vypsat primo nazvy klaves vedle hvezdicky podle selCh
                    text(x_text,80,['*' klavesy(logical(selCh(chselo,:)))], 'FontSize', 12,'Color','red');
                end
                if ~isempty(label)
                    text(x_text,-75,strrep(label,'_','\_'), 'FontSize', 10,'Color','blue' );
                end
                if isfield(obj.plotCh2D,'chshowstr') && ~isempty(obj.plotCh2D.chshowstr)
                    text(0,-90,['chshow:' obj.plotCh2D.chshowstr] ,'Color','red');
                end
            end
            
            if obj.plotCh2D.names %if channel labels should be plotted               
                text(y(obj.plotCh2D.ch_displayed),z(obj.plotCh2D.ch_displayed),chnnames,'FontSize', 8);                
            end
            
            if obj.plotCh2D.chseltop>1, uistack(h_selection, 'top'); end %the one selected channel topmost
            axis equal;
            if isfield(obj.plotCh2D,'grid') && obj.plotCh2D.grid==1
                grid on;
            end
            set(gca, 'YTick',-80:10:80); %yticks(-80:10:80);
            set(gca, 'XTick',-100:10:70); %xticks(-100:10:70);
            xlabel('MNI Y'); %predozadni souradnice
            ylabel('MNI Z'); %hornodolni
            if isfield(obj.plotCh2D,'background') && obj.plotCh2D.background==0
                set(gca,'color','none'); %zadne bile pozadi, pak ani v corelu
            end
            
            %rozhybani obrazku            
            set(obj.plotCh2D.fh,'KeyPressFcn',@obj.hybejPlot2D); 
            set(obj.plotCh2D.fh, 'WindowButtonDownFcn', @obj.hybejPlot2Dclick);
        end
%         function obj = SaveAUCPlotHandle(obj,fh) 
%             obj.plotCh2D.plotAUCH = fh; %ulozim handle na CStat.AUCPlot funkci,abych ji mohl volat z grafu ChannelPlot2D
%         end
        function tag= PacientTag(obj,ch)
            %vraci tag pacienta, napriklad p73
            if strcmp(obj.classname,'CHilbertMulti') && exist('ch','var') && ch > 0
                str = split(obj.H.channels(ch).name);
                tag = str{1}; %pokud se jedna o CHilbertMulti a zadam cislo kanalu, vracim cislo pacienta z tohoto kanalu
            else
                if isfield(obj.H,'patientTag'), tag = obj.H.patientTag; else, tag=obj.H.subjName; end
            end
        end
        function [MNI_coors]= GetMNI(obj,channels)   
            %vraci koordinaty MNI pro Jirkovy skripty na SEEG-vizualizaci
            if ~exist('channels','var'), channels = 1:size(obj.H.channels,2); end
            MNI_coors = repmat(struct('MNI_x',0,'MNI_y',0,'MNI_z',0),1,numel(channels));
            
            for ch = 1:numel(channels)
                if strcmpi(obj.H.channels(ch).signalType,'SEEG')
                     MNI_coors(ch).MNI_x = obj.H.channels(ch).MNI_x;
                     MNI_coors(ch).MNI_y = obj.H.channels(ch).MNI_y;
                     MNI_coors(ch).MNI_z = obj.H.channels(ch).MNI_z;
                end
            end
        end
        function [names,neurologyLabels]=GetChNames(obj,channels)
            %vrati jmena vsech kanalu jako cell array
            if ~exist('channels','var'), channels = 1:size(obj.H.channels,2); end
            names = cell(numel(channels),1);
            neurologyLabels = cell(numel(channels),1);
            for ch = 1: numel(channels)
                if strcmpi(obj.H.channels(ch).signalType,'SEEG')
                    names{ch}=obj.H.channels(ch).name;
                    neurologyLabels{ch}=obj.H.channels(ch).neurologyLabel;
                end
            end
        end
        function [epiInfo]=GetChEpiInfo(obj,channels)
            %vrati info epilepsii v kanalech - 1vs0vsNaN - seizureOnset a interictalOften dohromady
            if ~exist('channels','var'), channels = 1:size(obj.H.channels,2); end
            if isfield(obj.H.channels,'seizureOnset')
                epiInfo = double([obj.H.channels(channels).seizureOnset]' |  [obj.H.channels(channels).interictalOften]'); %vrati 1 pokud je jedno nebo druhe 1
            else
                epiInfo = nan(numel(channels),1); %neznam epiinfo
                warning(['no epiinfo in the header: ' obj.H.subjName]);
            end
        end            
        function tch = GetTriggerCh(obj)
            %ziska cislo trigerovaciho kanalu, pokud existuje
            tch = find(strcmp({obj.H.channels.signalType}, 'triggerCh')==1);         
        end
        function [tch,obj] = SetTriggerCh(obj,tch,trigger)
            %nastavi, ze kanal je trigger
            if ~exist('trigger','var'), trigger = 1; end 
            if trigger == 1  %defaultne nastavi, ze kanal je trigger
                obj.H.channels(tch).signalType = 'triggerCh';
                obj.H.triggerCH = tch;
            else
                obj.H.channels(tch).signalType = 'SEEG'; %nebo nastavi ze to naopak neni trigger
                obj.H.triggerCH = [];
            end
            tch = find(strcmp({obj.H.channels.signalType}, 'triggerCh')==1);
        end
        function [obj]= SetFilterMatrix(obj,filterMatrix)
            %ulozi filterMatrix pri zmene reference pro pozdejsi pouziti pri RjEpochCh
            obj.filterMatrix = filterMatrix;
        end
        function [obj]= SetSelCh(obj,selCh,selChNames,force)
            %SETSELCH - sets plotCh2D.selCh and selChNames
            %force means it sets selCh and  selChNames even if empty
            if ~exist('force','var'), force = 0; end
            if exist('selCh','var') && ( ~isempty(selCh) || force)
                obj.plotCh2D.selCh = selCh;
            end
            if exist('selChNames','var') && (~isempty(selChNames) || force)
                obj.plotCh2D.selChNames = selChNames;
            end
        end
        function [mozek] = GetBrainNames(obj) 
            % najde popisy mist v mozku podle tabulky od Martina    
            % TODO, co kdyz jmeno obsahuje pomlcku nebo zavorku?
            BA = load('BrainAtlas_zkratky.mat'); %nactu tabulku od Martina Tomaska, 
            obj.BrainAtlas_zkratky = BA.BrainAtlas_zkratky; %ulozim do obj.BrainAtlas_zkratky
            % sloupce plnynazev, structure,region, zkratka, alt zkratka 2-4            
            mozek = cell(numel(obj.sortorder),6);            
            for ich=1:numel(obj.sortorder)  %kanaly podle aktualniho filtru              
                ch = obj.sortorder(ich);
                mozek{ich,1} = ch;
                mozek{ich,2} = obj.H.channels(ch).name; %jmeno kanalu
                mozek{ich,3} = obj.H.channels(ch).neurologyLabel; %neurologyLabel
                [C,matches] = strsplit(obj.H.channels(ch).neurologyLabel,{'(',')','-','/'},'CollapseDelimiters',false);                
                structure = cell(numel(C),2);
                for j = 1:numel(C) %pro kazdou strukturu v neurologylabel
                    [C{j},structure(j,:)] = obj.brainlabel(C{j});  %predelam zkratku na plny nazev                  
                end
                mozek{ich,4} = strjoin(C,matches);  %puvodni label zase slozim, pri pouziti plnych jmen struktur
                %structure(cellfun(@isempty,C),:) = []; %vymazu ty casti structure, pro ktere nebyl zadny match
                mozek{ich,5} = CHHeader.joinNoDuplicates(structure(:,1),matches); 
                mozek{ich,6} = CHHeader.joinNoDuplicates(structure(:,2),matches);                 
            end
        end
        function [seizureOnset,interIctal]=GetSeizures(obj)
            %vrati indexy kanalu, ktere maji seizureOnset=1 nebo interictalOften=1
            if isfield(obj.H.channels,'seizureOnset')
               seizureOnset = find(cellfun(@any,{obj.H.channels.seizureOnset}));
               interIctal = find(cellfun(@any,{obj.H.channels.interictalOften}));
            else
               seizureOnset = [];
               interIctal = [];
            end    
        end
        function obj = ChangeReference(obj,ref)
            assert(any(ref=='heb'),'neznama reference, mozne hodnoty: h e b');
            H = obj.H;  %kopie headeru
            switch ref %jaky typ reference chci
                case 'h'  %headbox          
                    filterSettings.name = 'car'; % options: 'car','bip','nan'
                    filterSettings.chGroups = 'perHeadbox';        % options: 'perHeadbox' (=global CAR), OR 'perElectrode' (=local CAR per el. shank)
                case 'e'  %elektroda
                    filterSettings.name = 'car'; % options: 'car','bip','nan'
                    filterSettings.chGroups = 'perElectrode';        % options: 'perHeadbox' (=global CAR), OR 'perElectrode' (=local CAR per el. shank)
                case 'b'  %bipolarni
                    filterSettings.name = 'bip'; % options: 'car','bip','nan'           
            end
            filterMatrix = createSpatialFilter_kisarg(H, numel(H.selCh_H), filterSettings,obj.RjCh); %ve filterMatrix uz nejsou rejectovane kanaly                        
                %assert(size(rawData,2) == size(filterMatrix,1));            
            if ref=='b' %u bipolarni reference se mi meni pocet kanalu
                H.channels = struct; 
                selCh_H = zeros(1,size(filterMatrix,2)); 
                for ch = 1:size(filterMatrix,2) % v tehle matrix jsou radky stare kanaly a sloupce nove kanaly - takze cyklus pres nove kanaly
                    oldch = find(filterMatrix(:,ch)==1); %cislo stareho kanalu ve sloupci s novym kanalem ch
                    fnames = fieldnames(obj.H.channels(oldch)); %jmena poli struktury channels
                    for f = 1:numel(fnames) %postupne zkopiruju vsechny pole struktury, najednou nevim jak to udelat
                        fn = fnames{f};
                        H.channels(ch).(fn) = obj.H.channels(oldch).(fn); 
                    end
                    H.channels(ch).name = ['(' H.channels(ch).name '-' obj.H.channels(filterMatrix(:,ch)==-1).name ')']; %pojmenuju kanal jako rozdil
                    H.channels(ch).neurologyLabel = ['(' H.channels(ch).neurologyLabel '-' obj.H.channels(filterMatrix(:,ch)==-1).neurologyLabel ')'];  %oznaceni od Martina Tomaska
                    H.channels(ch).ass_brainAtlas = ['(' H.channels(ch).ass_brainAtlas '-' obj.H.channels(filterMatrix(:,ch)==-1).ass_brainAtlas ')']; 
                    MNI = [ H.channels(ch).MNI_x H.channels(ch).MNI_y H.channels(ch).MNI_z; ... 
                           obj.H.channels(filterMatrix(:,ch)==-1).MNI_x obj.H.channels(filterMatrix(:,ch)==-1).MNI_y obj.H.channels(filterMatrix(:,ch)==-1).MNI_z ...
                           ]; %matice MNI souradnic jednoho a druheho kanalu
                    MNI2=(MNI(1,:) + MNI(2,:))/2; % prumer MNI souradnic - nova souradnice bipolarniho kanalu
                    H.channels(ch).MNI_x =  MNI2(1); 
                    H.channels(ch).MNI_y =  MNI2(2); 
                    H.channels(ch).MNI_z =  MNI2(3); 
                    H.channels(ch).MNI_dist = sqrt( sum((MNI(1,:) - MNI(2,:)).^2));  %vzdalenost mezi puvodnimi MNI body                                                           
                    selCh_H(ch) = ch;
                end 
                H.selCh_H = selCh_H; 
%                 obj.ChangeReferenceRjEpochCh(filterMatrix); %prepocitam na bipolarni referenci i RjEpochCh                                
            end
            obj.H = H; %prepisu puvodni ulozeny header
            switch ref
                case 'h', obj.reference = 'perHeadbox'; 
                case 'e', obj.reference = 'perElectrode';  
                case 'b', obj.reference = 'Bipolar';  obj.ChannelGroups([],[],1); %forcechgroups , recompute channel groups and els
            end
            obj.SetFilterMatrix(filterMatrix); %uchovam si filterMatrix na pozdeji, kvuli prepoctu RjEpochCh
        end
        function obj = SortChannels(obj,by)
            %seradi kanaly podle vybrane MNI souradnice a ulozi do sortorder                        
            if isfield(obj.plotCh2D,'chshow') 
                chshow = obj.plotCh2D.chshow; %indexy aktualne vybranych kanalu
            else
                chshow = 1:numel(obj.H.channels); %seznam vsech kanalu
            end
            if ~exist('by','var')                
                obj.sortorder = chshow;                
                obj.sortedby = '';
            elseif strcmp(by,'x')
                [~,sortorder]=sort([obj.H.channels(chshow).MNI_x]);                
                obj.sortorder = chshow(sortorder);
                obj.sortedby = 'x';
            elseif strcmp(by,'y')
                [~,sortorder]=sort([obj.H.channels(chshow).MNI_y]);                
                obj.sortorder = chshow(sortorder);
                obj.sortedby = 'y';
            elseif strcmp(by,'z')
                [~,sortorder]=sort([obj.H.channels(chshow).MNI_z]); 
                obj.sortorder = chshow(sortorder);
                obj.sortedby = 'z';
            else
                disp(['nezname razeni podle ' by]); 
            end
        end
        function obj = NextSortChOrder(obj) 
            %zmeni na dalsi razeni kanalu v poradi, podle MNI souradnic
            switch obj.sortedby
               case ''
                   obj.SortChannels('x');
               case 'x'
                   obj.SortChannels('y');
               case 'y'
                   obj.SortChannels('z');
               case 'z'
                   obj.SortChannels();
            end 
        end
        function obj = FilterChannels(obj,chlabels,notchnlabels,selCh, chnum,label)
            %vyberu podle neurologylabel jen nektere kanaly k zobrazeni
            %selCh - jedno pismeno fghjkl podle oznaceni kanalu. 
            %chnum - primo zadam cisla kanalu k filtrovani
            %label - muzu nazvat vyber jak potrebuju
            % Pozor - funguje na zaklade obj.plotCh2D.selCh, ktere se vytvari pri volani ChannelPlot2D, takze to se musi spusti nejdriv a i po zmene vyberu kanalu
            % 15.1.2020 - can use more filters, the function uses AND between them = intersect
            
            filtered = false; 
            chshow = 1:numel(obj.H.channels); %show all channels by default
            chshowstr = {}; %label of the filter
            if exist('chlabels','var') && ~isempty(chlabels)
                if strcmp(chlabels{1},'label')
                    ChLabels = {obj.brainlabels(:).label}';
                    chlabels = chlabels(2:end); 
                    showstr = 'label=';
                elseif strcmp(chlabels{1},'lobe')
                    ChLabels = {obj.brainlabels(:).lobe}';
                    chlabels = chlabels(2:end);
                    showstr = 'lobe=';
                elseif strcmp(chlabels{1},'class')
                    ChLabels = {obj.brainlabels(:).class}';
                    chlabels = chlabels(2:end);
                    showstr = 'class=';
                else
                    ChLabels = {obj.H.channels(:).neurologyLabel}';
                    showstr = 'nlabel=';
                end                
                iL = contains(lower(ChLabels),lower(chlabels)); %prevedu oboji na mala pismena
                if exist('notchnlabels','var') && numel(notchnlabels) > 0
                    iLx = contains(lower(ChLabels),lower(notchnlabels));
                    iL = iL & ~iLx;
                    chshowstr = [showstr cell2str(chlabels) ' not:' cell2str(notchnlabels)];
                else
                    chshowstr = [showstr cell2str(chlabels)];
                end
                chshow = intersect(chshow,find(iL)'); %reduce list of channels to show                                               
                filtered = true;
            end
            if exist('selCh','var') && ~isempty(selCh)
                klavesy = 'fghjkl';
                assert (numel(selCh)<=4,'maximum of 4 letter could be in selCh ');
                if find(ismember(klavesy,selCh)) %vrati index klavesy nektereho selCh v klavesy
                    if ~isfield(obj.plotCh2D,'selCh')
                        warning('No selCh in CH object, first run the ChannelPlot2D');
                    else                        
                        chshow = intersect(chshow,find(obj.plotCh2D.selCh(:,ismember(klavesy,selCh)))'); %indexy kanalu se znackou f-l                    
                        chshowstr = horzcat(chshowstr, {klavesy(ismember(klavesy,selCh))}); 
                        filtered = true;  
                    end
                end
                if ismember('r',selCh) %rejected channels, nekde v selCh je r
                    chshow = intersect(chshow,obj.RjCh);
                    chshowstr = horzcat(chshowstr, {'Rj'}); 
                    filtered = true;
                elseif ismember('n',selCh) %NOT rejected channels,, nekde v selCh je r
                    chshow = intersect(chshow,setdiff(obj.H.selCh_H,obj.RjCh));
                    chshowstr = horzcat(chshowstr, {'nRj'}); 
                    filtered = true;
                end
                if contains(selCh, '~e')    % not epileptic je dvojice znaku "~e"
                    flt = [obj.H.channels.seizureOnset] == 0 & [obj.H.channels.interictalOften] == 0;
                    chshow = intersect(chshow,find(flt));
                    chshowstr = horzcat(chshowstr, {'~Epi'}); 
                    filtered = true;
                elseif contains(selCh, 'e') % epileptic je pouze "e" (mohlo by se pouzit i ismemeber)
                    flt = [obj.H.channels.seizureOnset] == 1 | [obj.H.channels.interictalOften] == 1;
                    chshow = intersect(chshow,find(flt));
                    chshowstr = horzcat(chshowstr, {'Epi'}); 
                    filtered = true;
                end                                               
            end
            if exist('chnum','var') && ~isempty(chnum)
                if size(chnum,1) > size(chnum,2), chnum = chnum'; end %chci mit cisla kanalu v radku
                chshow = intersect(chnshow,chnum); %priradim primo cisla kanalu                
                if exist('label','var') && ~isempty(label)
                    chshowstr = horzcat(chshowstr,{labels});
                else
                    chshowstr = horzcat(chshowstr,{'chnum'});
                end
                filtered = true;
            end
            if filtered
                obj.plotCh2D.chshow = chshow;
                obj.sortorder = obj.plotCh2D.chshow;                    
                if ~ischar(chshowstr) 
                    obj.plotCh2D.chshowstr = strjoin(chshowstr,' & '); 
                else
                    obj.plotCh2D.chshowstr = chshowstr;
                end
                disp(['shown ' num2str(numel(obj.plotCh2D.chshow)) ' channels: ' obj.plotCh2D.chshowstr]); 
            else            
                obj.plotCh2D.chshow = 1:numel(obj.H.channels);
                obj.plotCh2D.chshowstr = '';
                obj.sortorder = 1:numel(obj.H.channels); %defaultni sort order pro vsechny kanaly
                disp('all channels shown');
            end
            notify(obj, 'FilterChanged');
        end
        function obj = BrainLabelsImport(obj,brainlbs,filename)
            %naimportuje cell array do struct array. Hlavne kvuli tomu, ze v cell array nemusi byt vsechny kanaly
            %predpoklada ctyri cloupce - cislo kanalu, brainclass	brainlabel	lobe
            %filename - jmeno CHilbertMulti _CiEEG.mat souboru, ze ktereho se maji brainlabels najit podle jmen kanalu
            
            if isempty(brainlbs) && exist('filename','var')
                 assert(exist(filename,'file')==2,'soubor filename neexistuje');
                 vars = whos('-file',filename) ;
                 assert(ismember('CH_H', {vars.name}), 'soubor neobsahuje promennou H'); 
                 assert(ismember('CH_brainlabels', {vars.name}), 'soubor neobsahuje promennou brainlabels'); 
                 CH = load(filename,'CH_H','CH_brainlabels'); %nactu do struktury
                 names = {CH.CH_H.channels.name};
                 loaded = 0; %pocet nactenych kanalu
                 for ch = 1:numel(obj.H.channels)
                     idx = find(ismember(names,obj.H.channels(ch).name));
                     if ~isempty(idx)
                        obj.brainlabels(ch).class = CH.CH_brainlabels(idx).class;
                        obj.brainlabels(ch).label = CH.CH_brainlabels(idx).label;
                        obj.brainlabels(ch).lobe = CH.CH_brainlabels(idx).lobe;
                        loaded = loaded + 1;
                     end 
                 end                 
            else
                %BL = struct('class',{},'label',{},'lobe',{}); %empty struct with 3 fields
                %nechci mazat ty existujici, to muzu kdyz tak udelat rucne
                loaded = 0; %pocet nactenych kanalu
                for j = 1:size(brainlbs,1)
                    obj.brainlabels(brainlbs{j,1}).class = brainlbs{j,2};
                    obj.brainlabels(brainlbs{j,1}).label = brainlbs{j,3};
                    obj.brainlabels(brainlbs{j,1}).lobe = brainlbs{j,4};
                    loaded = loaded + 1;
                end    
                %obj.brainlabels = BL;
            end
            disp(['loaded brainlabels of ' num2str(loaded) ' channels']);
            %chci mit vsude string, zadne prazdne, kvuli exportu. Takze prazdna nahradim mezerou
            BL = obj.brainlabels';
            emptyIndex = find(arrayfun(@(BL) isempty(BL.class),BL)); %nasel jsem https://www.mathworks.com/matlabcentral/answers/328326-check-if-any-field-in-a-given-structure-is-empty
            if ~isempty(emptyIndex)
                for j = emptyIndex'
                    BL(j).class = ' '; %nejaky znak asi musim vlozit
                end
            end
            emptyIndex = find(arrayfun(@(BL) isempty(BL.label),BL)); %nasel jsem https://www.mathworks.com/matlabcentral/answers/328326-check-if-any-field-in-a-given-structure-is-empty
            if ~isempty(emptyIndex)
                for j = emptyIndex'
                    BL(j).label = ' ';
                end
            end
            emptyIndex = find(arrayfun(@(BL) isempty(BL.lobe),BL)); %nasel jsem https://www.mathworks.com/matlabcentral/answers/328326-check-if-any-field-in-a-given-structure-is-empty
            if ~isempty(emptyIndex)
                for j = emptyIndex'
                    BL(j).lobe = ' ';
                end  
            end
            obj.brainlabels = BL;
        end
        function obj = RemoveChannels(obj,channels)  
            %smaze se souboru vybrane kanaly. Kvuli redukci velikost aj                        
            keepch = setdiff(1:numel(obj.H.channels),channels); %channels to keep            
            channelmap = zeros(1,numel(obj.H.channels));
            channelmap(keepch) = 1:numel(keepch); %prevod ze starych cisel kanalu na nove
            
            obj.RjCh = setdiff(obj.RjCh,channels,'stable'); %kanaly ktere zbydou s puvodnimi cisly
            obj.RjCh = channelmap(obj.RjCh); %nova cisla zbylych kanalu
            
            obj.H.channels = obj.H.channels(keepch);
            obj.H.selCh_H = channelmap(setdiff(obj.H.selCh_H,channels,'stable')); %keep the order             
            %kanaly musim precislovat, napriklad z 11 se ma stat 4 atd            
            obj.sortorder = channelmap(setdiff(obj.sortorder,channels,'stable')); %cisla 1:n v poradi puvodniho sortorder   
            if isprop(obj,'plotCh2D') && isfield(obj.plotCh2D,'chshow')
                obj.plotCh2D.chshow = channelmap(setdiff(obj.plotCh2D.chshow,channels,'stable')); 
                obj.plotCh2D.ch_displayed = channelmap(setdiff(obj.plotCh2D.ch_displayed,channels,'stable')); 
            end
            
            %TODO - vyradit i radky z obj.brainlabels
            obj.filterMatrix = obj.filterMatrix(:,keepch'); 
            for j = 1:numel(obj.els)
                if j == 1
                    n = sum(channels<=obj.els(j));
                else
                    n = sum(channels > obj.els(j-1) & channels < obj.els(j));
                end
                if n > 0
                    obj.els(j:end) = obj.els(j:end) - n; %potrebuju snizit i vsechny nasledujici
                else
                    obj.els(j) = [];
                end
            end
            for j = 1:numel(obj.chgroups)
                obj.chgroups{j} = channelmap(setdiff( obj.chgroups{j},channels,'stable'));
            end
        end
        function obj = BrainLabels2XLS(obj,xlslabel,includeRjCh,computehull)
            %BRAINLABELS2XLS - exports number of channels and pacients for all brainlabels
            %is function of CHHeader and uses channel marks from obj.plotCh2D.selChNames
            %this values needs to be updated by obj.ChannelPlot2D after change in CiEEGData, i.e. by pressing Enter in PlotResponseCh           
            assert(length(obj.brainlabels)==numel(obj.H.channels),'Different no of brainlabels than channels in header');
            if ~exist('xlslabel','var') || isempty(xlslabel) , xlslabel = ''; end
            if ~exist('includeRjCh','var') || isempty(includeRjCh) , includeRjCh = 0; end %
            if ~exist('computehull','var') || isempty(computehull) , computehull = 0; end
            labels = lower({obj.brainlabels.label}); %cell array of brainlabels
            ulabels = unique(labels); 
            noMarks = sum(~cellfun(@isempty,obj.plotCh2D.selChNames)); %number of used marks fghjkl
            output = cell(numel(ulabels),4+noMarks*2); %columns label,noChannels, noPacients,noRejected, noChInMarks fghjkl 1-6, noPacInMarks
            hulldata = cell(numel(ulabels),5);
            selChNamesPac = cell(1,noMarks);
            for m=1:noMarks
                selChNamesPac{m} = [obj.plotCh2D.selChNames{m} 'NoPac']; %name for this count of pacients
            end
            varnames = horzcat({'brainlabel','count','patients','rejected'},obj.plotCh2D.selChNames(1:noMarks),selChNamesPac);
            for j = 1:numel(ulabels) %cycle over all brainlabels
               chIndex = find(contains(labels,ulabels{j})); 
               if ~includeRjCh, chIndex = setdiff(chIndex,obj.RjCh); end %channels without the rejected channels
               pTags = cell(numel(chIndex),1); %pacient name for each channel for this labels
               for ch = 1:numel(chIndex)
                   pTags{ch}=obj.PacientTag(chIndex(ch));
               end
               rjCount = numel(intersect(chIndex,obj.RjCh)); %number of rejected channels for this label
               marksCount =  sum(obj.plotCh2D.selCh(chIndex,1:noMarks)); %count of channel marking fghjkl        
               marksPacientCount = zeros(1,noMarks);               
               for m=1:noMarks
                   marksPacientCount(m) = numel(unique(pTags(logical(obj.plotCh2D.selCh(chIndex,m))))); %no of patients for this mark                  
               end
               output(j,:)=[ ulabels(j) num2cell([(numel(chIndex)),numel(unique(pTags)),rjCount,marksCount, marksPacientCount])];
               if computehull 
                   if numel(chIndex)>0
                       mni = [[obj.H.channels(chIndex).MNI_x];[obj.H.channels(chIndex).MNI_y];[obj.H.channels(chIndex).MNI_z]]';
                       imni_left = mni(:,1) < 0; %left side channels                       
                       kh_left = boundary(mni(imni_left,1),mni(imni_left,2),mni(imni_left,3)); %,'Simplify',true
                       imni_right = mni(:,1) >= 0; %right side channels                      
                       kh_right = boundary(mni(imni_right,1),mni(imni_right,2),mni(imni_right,3)); %,'Simplify',true
                       hulldata(j,:) = {ulabels{j},chIndex(imni_left),chIndex(imni_right),kh_left,kh_right};                                      
                   else 
                       hulldata(j,:) = {ulabels{j},[],[],[],[]};                                      
                   end
                   
               end
            end
            if computehull
                obj.hull = hulldata;
                disp('convex hull saved');
            else
                xlsfilename = ['./logs/BrainLabels2XLS' '_' xlslabel '_' datestr(now, 'yyyy-mm-dd_HH-MM-SS')];
                xlswrite(xlsfilename ,vertcat(varnames,output)); %write to xls file
                disp([xlsfilename '.xls with ' num2str(size(output,1)) ' lines saved']);
            end
            
        end
        function obj = HullPlot3D(obj,iLabel)
            if isfield(obj.channelPlot.plotCh3D,'fh') && ishandle(obj.channelPlot.plotCh3D.fh)
                if iLabel > 0 %iLabel 0 means to plot no hull in the 3D figure
                    figure(obj.channelPlot.plotCh3D.fh); %activate 3D figure

                    % left side channels
                    ich = obj.hull{iLabel,2}; 
                    mni = [[obj.H.channels(ich).MNI_x];[obj.H.channels(ich).MNI_y];[obj.H.channels(ich).MNI_z]]';
                    kh = obj.hull{iLabel,4};
                    trisurf(kh,mni(:,1),mni(:,2),mni(:,3),'Facecolor','none'); %,'Facecolor','red','FaceAlpha',0.1           

                    %right side channels
                    ich = obj.hull{iLabel,3}; 
                    mni = [[obj.H.channels(ich).MNI_x];[obj.H.channels(ich).MNI_y];[obj.H.channels(ich).MNI_z]]';
                    kh = obj.hull{iLabel,5};
                    trisurf(kh,mni(:,1),mni(:,2),mni(:,3),'Facecolor','none');                           
                end
                
                obj.channelPlot.plotCh3D.hullindex = iLabel;
            else
                disp('no ChannelPlot figure to plot in');
            end
        end
        
    end
    
    %  --------- privatni metody ----------------------
    methods (Access = private)
          function obj = SelChannels(obj)
            % selected channels: signal type = iEEG
            % kopie z exampleSpatialFiltering.m
            selCh_H = [];
            selSignals = {'SEEG', 'ECoG-Grid', 'ECoG-Strip'};           % select desired channel group
            for ch = 1:size(obj.H.channels,2)
                if isfield(obj.H.channels(ch), 'signalType')
                    if ismember(obj.H.channels(ch).signalType, selSignals)
                        selCh_H = [selCh_H, ch]; %#ok<AGROW> %obj.H.channels(ch).numberOnAmplifier - kamil 14.6.2016 numberOnAmplifier nefunguje v pripade bipolarni reference kde jsou jina cisla kanalu
                    end
                end
            end
            
            obj.H.selCh_H = selCh_H;
          end  
          function groups = getChannelGroups(obj,subjname,chnsel)
             %vraci cell array, kazda bunka jsou cisla kanalu ve skupine
             % subjname - jestli jsou skupiny podle subjname (napr p173) nebo elektrod (napr A)             
             
             if ~exist('subjname','var') || isempty(subjname), subjname = iff(  strcmp(obj.classname,'CHilbertMulti')'); end %defaultne podle elektod
             if ~exist('chnsel','var') || isempty(chnsel), chnsel = 1:numel(obj.H.channels); end %defaultne podle elektod
             strprev = '';
             groups = cell(1,1);
             groupN = 1;
             chgroup = [];             
             if subjname
                expr = '^\w+'; %pismena i cisla,napriklad p173, konci mezerou nebo zavorkou za tim
             elseif strcmp(obj.reference,'Bipolar') && obj.H.channels(1).name(1) == '(' % ustarych data jsou bipolarni nazvy bez zavorky
                expr = '^\(([a-zA-Z]+)';
             else
                expr = '^[a-zA-Z]+';
             end
             iSEEG = find(strcmp({obj.H.channels.signalType}, 'SEEG')==1); %index kanalu, ktere jsou SEEG. Protoze u deti muze byt i na zacatku
             chnsel = intersect(chnsel,iSEEG); %prunik obou seznamu kanalu
             for ch = chnsel
                     str = regexp(obj.H.channels(ch).name,expr,'match');   %jeden nebo vice pismen na zacatku                  
                     if ~strcmp(str{1},strprev) %jiny nez predchozi pacient/elektroda
                         if ch ~= chnsel(1) %pokud to neni prvni kanal
                            groups{groupN} = chgroup; %uzavru skupinu
                            groupN = groupN + 1;                            
                         end
                         chgroup = ch;
                         strprev = str{1};    
                     else %stejny pacient/elektroda jako u minuleho kanalu
                         chgroup = [chgroup ch]; %#ok<AGROW>
                     end
             end
             groups{groupN} = chgroup;
          end
          function [bl,structure] = brainlabel(obj,label)
            %vrati jmeno struktury podle tabulky, pripadne doplni otaznik na konec             
            if isempty(label)
                bl = ''; structure={'',''}; return; 
            end
            znak = strfind(label,'?');
            if ~isempty(znak)
                label = label(1:znak-1); % label bez otazniku
            end
            iL = ''; %index=radek v BrainAtlas_zkratky
            col = 3; %slopec ve zkratkach v BrainAtlas_zkratky
            %nejdriv zkusim najit presny vyskyt
            while isempty(iL) && col < size(obj.BrainAtlas_zkratky,2)
                col = col + 1; %zkratky zacinaji v ctvrtem sloupci
                if isempty(obj.BrainAtlas_zkratky(:,col)) %pokud je tahle alternativa zkratky prazdna, nebudu hledat dal
                    break; 
                end
                iL = find(strcmpi(obj.BrainAtlas_zkratky(:,col),label)); %nezavisle na velikosti pismen
            end
            if isempty(iL) %zadne label nenalezeno
                bl = '';  structure={'',''};
            elseif(numel(iL)>1) % vic nez jedno label nalezeno
                bl = [num2str(numel(iL)) ' labels'];
                structure={'',''}; 
            else
                bl = obj.BrainAtlas_zkratky{iL,1};            
                if ~isempty(znak)
                    bl = [bl '?'];
                end
                structure={obj.BrainAtlas_zkratky{iL,2},obj.BrainAtlas_zkratky{iL,3}}; 
                structure(cellfun(@isempty,structure))={''}; %potrebuju mit prvky chararray
            end
          end         

          function obj = hybejPlot2D(obj,~,eventDat) 
              iCh = find(obj.plotCh2D.ch_displayed==obj.sortorder(obj.plotCh2D.chsel)); %index v obj.plotCh2D.ch_displayed
              switch eventDat.Key
                  case {'rightarrow','q'} %dalsi kanal
                      if numel(obj.plotCh2D.ch_displayed) >= iCh + 1
                        ch = min( [obj.plotCh2D.ch_displayed(iCh + 1), obj.plotCh2D.ch_displayed(end)]);
                        obj.ChannelPlot2D( find(obj.sortorder==ch)); %#ok<FNDSB>
                      end
                  case 'pagedown' %skok o 10 kanalu dopred
                      if numel(obj.plotCh2D.ch_displayed) >= iCh + 10
                        ch = min( [obj.plotCh2D.ch_displayed(iCh + 10) , obj.plotCh2D.ch_displayed(end)]);
                        obj.ChannelPlot2D( find(obj.sortorder==ch)); %#ok<FNDSB>
                      end
                  case {'leftarrow','e'} %predchozi kanal
                      if iCh - 1 >= 1
                        ch = max( [obj.plotCh2D.ch_displayed(iCh - 1) , obj.plotCh2D.ch_displayed(1)]);
                        obj.ChannelPlot2D( find(obj.sortorder==ch)); %#ok<FNDSB>
                      end
                  case 'pageup' %skok 10 kanalu dozadu
                      if iCh - 10 >= 1
                        ch = max( [obj.plotCh2D.ch_displayed(iCh - 10), obj.plotCh2D.ch_displayed(1)]);
                        obj.ChannelPlot2D( find(obj.sortorder==ch)); %#ok<FNDSB>
                      end
                  case 'return' %zobrazi obrazek mozku s vybranych kanalem                   
                      obj.plotCh2D.plotChH(obj.plotCh2D.chsel); %vykreslim @obj.PlotResponseCh                     
                      figure(obj.plotCh2D.fh); %dam puvodni obrazek dopredu
                  case 'home' %skok na prvni kanal
                      obj.ChannelPlot2D( find(obj.sortorder==obj.plotCh2D.ch_displayed(1))); %#ok<FNDSB>
                  case 'end' %skok na posledni kanal
                      obj.ChannelPlot2D( find(obj.sortorder==obj.plotCh2D.ch_displayed(end))); %#ok<FNDSB>
                  case 'period'     % prepinani razeni kanalu
                      sortorder0 = obj.sortorder; %musi si ulozit stare razeni, abych potom nasel ten spravny kanal
                      obj.NextSortChOrder();                   
                      obj.ChannelPlot2D(find(obj.sortorder==sortorder0(obj.plotCh2D.chsel))); %#ok<FNDSB> %takhle zustanu na tom stejnem kanale 
                  case {'numpad6','d'}     % skok na dalsi oznaceny kanal   
                    if isfield(obj.plotCh2D,'selCh') 
                       selCh = find(any(obj.plotCh2D.selCh,2)); %seznam cisel vybranych kanalu
                       iselCh = find(ismember(obj.sortorder,selCh)); %indexy vybranych kanalu v sortorder
                       chn2 = iselCh(find(iselCh>obj.plotCh2D.chsel,1)); %dalsi vyznaceny kanal
                       obj.ChannelPlot2D( iff(isempty(chn2),obj.plotCh2D.chsel,chn2) ); %prekreslim grafy                        
                    end                   
                  case {'numpad4','a'}     % skok na predchozi oznaceny kanal
                    if isfield(obj.plotCh2D,'selCh')  
                       selCh = find(any(obj.plotCh2D.selCh,2)); %seznam cisel vybranych kanalu
                       iselCh = find(ismember(obj.sortorder,selCh)); %indexy vybranych kanalu v sortorder
                       chn2 =  iselCh(find(iselCh < obj.plotCh2D.chsel,1,'last')) ;
                       obj.ChannelPlot2D( iff(isempty(chn2),obj.plotCh2D.chsel,chn2) ); %prekreslim grafy
                    end
                  case 'space'
                     if isfield(obj.plotCh2D,'boundary') %prepinam v grafu cely scatter s jen hranici mozku - hlavne kvuli kopirovani do corelu
                         obj.plotCh2D.boundary  = 1 - obj.plotCh2D.boundary;
                     else
                         obj.plotCh2D.boundary  = 1;
                     end
                     obj.ChannelPlot2D();
                  case {'f','g','h'}
                      obj.plotCh2D.marks( eventDat.Key - 'f' + 1) = 1 - obj.plotCh2D.marks( eventDat.Key - 'f' + 1);
                      obj.ChannelPlot2D();
                  case {'j','k','l'}
                      obj.plotCh2D.marks( eventDat.Key - 'f' ) = 1 - obj.plotCh2D.marks( eventDat.Key - 'f' );
                      obj.ChannelPlot2D();
                  case {'tab'} %zapinani a vypinani gridu
                      if isfield(obj.plotCh2D,'grid') 
                          obj.plotCh2D.grid = 1-obj.plotCh2D.grid;
                      else
                         obj.plotCh2D.grid = 1;
                      end
                      obj.ChannelPlot2D();
                  case 'w' %zapinani a vypinani prazdneho pozadi obrazku
                      if isfield(obj.plotCh2D,'background') 
                          obj.plotCh2D.background = 1-obj.plotCh2D.background;
                      else
                         obj.plotCh2D.background = 0;
                      end
                      obj.ChannelPlot2D();
                  case 'p' %vybrany kanal je zluty na popredi /pozadi / hidden
                      obj.plotCh2D.chseltop = obj.plotCh2D.chseltop + 1;
                      if obj.plotCh2D.chseltop > 2, obj.plotCh2D.chseltop = 0; end %0-nezobrazen, 1-v pozadi, 2-v popredi
                      obj.ChannelPlot2D();
                  case 'n' %moznost vypnout / zapnout zobrazeni jmen kanalu
                      obj.plotCh2D.names = obj.plotCh2D.names + 1; 
                      if obj.plotCh2D.names == 4, obj.plotCh2D.names =0; end % meni se postupne hodoty 0 1 2
                      obj.ChannelPlot2D();    
                  case 's' %switch to show all channels 
                      obj.plotCh2D.lines = obj.plotCh2D.lines + 1;
                      if obj.plotCh2D.lines == 2, obj.plotCh2D.lines = -1; end %hodnoty -1 0 1, -1=nezobrazovat neoznacene kanaly, 0=nezobrazovat cary, 1=zobrazovat
                      obj.ChannelPlot2D();
                  case 't' %barvy oznaceni kanalu fghjkl jsou pruhledne nebo ne
                      obj.plotCh2D.transparent = 1-obj.plotCh2D.transparent;
                      obj.ChannelPlot2D();
                  case 'c' %prepinani index barevne skaly
                      obj.plotCh2D.color_index = 1+obj.plotCh2D.color_index;
                      if obj.plotCh2D.color_index > 6, obj.plotCh2D.color_index = 1; end
                      obj.ChannelPlot2D();  
                  case 'v' %prepinani view vlevo coronal/axial
                      obj.plotCh2D.coronalview = 1-obj.plotCh2D.coronalview;
                      obj.ChannelPlot2D();    
%                   case 'r' %zobrazi obrazek mozku s vybranych kanalem                   
%                       obj.plotCh2D.plotAUCH(obj.plotCh2D.chsel); %vykreslim @obj.PlotResponseCh    %tady to hlasi error Undefined function or variable 'obj.CS.AUCPlot'. Jak to?                  
%                       figure(obj.plotCh2D.fh); %dam puvodni obrazek dopredu     
              end              
          end
          function hybejPlot2Dclick(obj,h,~)
              mousept = get(gca,'currentPoint');
              x = mousept(1,1); y = mousept(1,2); %souradnice v grafu              
              xy = get(h, 'currentpoint'); %souradnice v pixelech
              pos = get(gcf, 'Position'); 
              width = pos(3);
              subp = xy(1) > width/2; 
              chns_mni = [];
              if isfield(obj.plotCh2D,'ch_displayed')
                  chshow = obj.plotCh2D.ch_displayed; %seznam skutecne zobrazenych kanaly
              elseif isfield(obj.plotCh2D,'chshow') && numel(obj.plotCh2D.chshow) < numel(obj.H.channels) 
                  chshow = obj.plotCh2D.chshow;
              else
                  chshow = 1:numel(obj.H.channels);
              end
              if subp == 0  %axialni graf, subplot 1
                  if x > -70 && x < 70 && y > -120 && y < 90
                    chns_mni = [[obj.H.channels(chshow).MNI_x]' , [obj.H.channels(chshow).MNI_y]'];                  
                  end
              else         %sagitalni graf, subplot 2
                  if x > -100 && x < 70 && y > -100 && y < 90
                    chns_mni = [[obj.H.channels(chshow).MNI_y]' , [obj.H.channels(chshow).MNI_z]'];   
                  end
              end
              if ~isempty(chns_mni)
                  [ch,~] = dsearchn(chns_mni,[x y]); %najde nejblizsi kanal a vzdalenost k nemu                   
                  obj.ChannelPlot2D(find(obj.sortorder==chshow(ch))); %#ok<FNDSB>   
                  if isfield(obj.plotCh2D,'plotChH')
                    obj.plotCh2D.plotChH(obj.plotCh2D.chsel); %vykreslim @obj.PlotResponseCh  
                    figure(obj.plotCh2D.fh); %dam puvodni obrazek dopredu
                  end
                  
              end
          end

    end
    methods (Access = private,Static)
         function str = joinNoDuplicates(C,delim)
              switch numel(C)
                  case 1 %nasel jsem i v bipolarni referenci neurologyLabel jen PHG, bez pomlcky a zavorek, nevim jak
                      str = C{1};
                  case 4 %jen dve struktury napriklad PHG-PHG
                      if strcmp(C{2},C{3})
                          str = strjoin(C([1 2 4]),delim([1 3]));
                      else
                          str = strjoin(C,delim); 
                      end
                  case 5 %tri struktury, treba PHG/FG-FG aj
                      if strcmp(C{2},C{3}) && strcmp(C{3},C{4}) %vsechny stejne
                          str = strjoin(C([1 2 5]),delim([1 4]));
                      elseif strcmp(C{2},C{3}) %prvni a druhy stejny
                          str = strjoin(C([1 2 4 5]),delim([1 3 4]));
                      elseif strcmp(C{3},C{4}) %druhy a treti stejny
                          str = strjoin(C([1 2 3 5]),delim([1 2 4]));
                      else
                          str = strjoin(C,delim); 
                      end
                  otherwise %ctyri struktury, napriklad PHG/FG-PHG/FG a ruzne jine divnosti
                      if strcmp(C{2},C{3}) && strcmp(C{3},C{4}) && strcmp(C{4},C{5}) 
                          str = strjoin(C([1 2 6]),delim([1 5]));
                      else      
                          if strcmp(C{4},C{5})
                            C(5)=[]; delim(4) = [];
                          end
                          if strcmp(C{2},C{3})
                            C(3)=[]; delim(2) = [];
                          end 
                          if numel(C)>=3 && isempty(C{2}), C(2) = []; delim(2) = []; end
                          if numel(C)>=4 && isempty(C{3}), C(3) = []; delim(2) = []; end
                          if numel(C)>=5 && isempty(C{4})
                              C(4) = []; delim(end-1) = []; 
                          end
                          if numel(C)>=6 && isempty(C{5}), C(5) = []; delim(end-1) = []; end                                                    
                          if numel(C)>=6 && strcmp(C{4},C{5})
                            C(5)=[]; delim(4) = [];
                          end
                          if numel(C)>=4 && strcmp(C{2},C{3})
                            C(3)=[]; delim(2) = [];
                          end
                          if numel(delim)>numel(C)+1, delim(2)=[]; end
                          delim{1} = '(';
                          delim{end}=')';
                          if(numel(delim)==3), delim{2} = '-'; end
                          str = strjoin(C,delim);                       
                      end                    
              end
         end         
    end
    
end

