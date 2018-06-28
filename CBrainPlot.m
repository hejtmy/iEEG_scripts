classdef CBrainPlot < matlab.mixin.Copyable
    %CBRAINPLOT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        VALS; %souhrnne prumery elektrod pres vsechny pacienty - cell(intervaly x kategorie)
        MNI;  %souhrnna MNI data pres vsechny pacienty - cell(intervaly x kategorie)
        NAMES; %souhrnna jmena elektrod pres vsechny pacienty - cell(intervaly x kategorie)
        intervals; % intervaly z funkce IntervalyResp
        katstr; %jmena kategorii
        brainsurface; %ulozeny isosurface z main_brainPlot
        testname; %jmeno zpracovavaneho testu
        katstr_pacients;
        numelP; %pocty  signif elektrod pro kazdy pacient x interval x kategorie
        pacients;    
        filename; %jmeno zpracovavanych souboru
        PAC; %struktura stejna jako vraci funkce StructFind, naplni se v IntervalyResp
        iPAC; %index v poli PAC
        reference; %reference
        Hf; %seznam frekvencnich pasem
    end
    
    methods (Access = public)        
        function [obj] = IntervalyResp(obj,testname,intervals,filename,contrast)
            %IntervalyResp(testname,intervals,filename,contrast)
            %vola postupne pro vsechny pacienty E.IntervalyResp a uklada vysledky
            %vyradi vsechny kontakty bez odpovedi nebo se zapornou odpovedi
            %spoji vsechno dohromady
            %vrati vysledky ve formatu pro SEEE-vizualization
            %napr CB.IntervalyResp('aedist',[0.2 0.8],'AEdist CHilbert 50-120 refBipo Ep2017-11_CHilb.mat');
            if ~exist('contrast','var'), contrast = 1; end; %defaultni je prvni kontrast            
            if strcmp(testname,'aedist')
                pacienti = pacienti_aedist(); %nactu celou strukturu pacientu    
            elseif strcmp(testname,'ppa')
                pacienti = pacienti_ppa(); %nactu celou strukturu pacientu    
            elseif strcmp(testname,'menrot')
                pacienti = pacienti_menrot(); %nactu celou strukturu pacientu    
            else
                error('neznamy typ testu');
            end
            obj.testname = testname;
            obj.intervals = intervals; 
            obj.filename = filename;
            elcount = []; %jen inicializace            
            P = {}; M = {}; N = {}; %jen inicializace
            obj.PAC = [];
            obj.pacients = cell(numel(pacienti),1); 
            obj.katstr_pacients = []; %musim to smazat, nize testuju, jestil to je prazdne
            obj.numelP = [];  %tam budu ukladat pocty elektrod pro kazdy pacient x interval x kategorie
            for p = 1:numel(pacienti) % cyklus pacienti
                if pacienti(p).todo 
                    disp(['***   ' pacienti(p).folder '   ***']);
                    E = pacient_load(pacienti(p).folder,testname,filename,[],[],[],0); %nejspis objekt CHilbert, pripadne i jiny; loadall = 0
                    if isempty(E)
                        disp('no data');
                        pacienti(p).todo = 0; %nechci ho dal zpracovavat
                        continue;
                    end
                    E.SetStatActive(contrast); %nastavi jeden z ulozenych statistickych kontrastu
                    [prumery, MNI,names,~,katstr] = E.IntervalyResp( intervals,[],0);   %#ok<PROPLC> %no figure, funkce z CiEEGData                           
                    obj.pacients{p} = pacienti(p).folder;
                    obj.GetPAC(prumery,E.CH.H,pacienti(p).folder);
                    obj.reference = E.reference;
                    obj.Hf = E.Hf;
                    clear E;
                    if isempty(obj.katstr_pacients)
                        obj.katstr = [katstr 'AllEl']; %#ok<PROPLC> %katstr se ziskava z IntervalyResp
                        obj.katstr_pacients = cell(numel(pacienti),numel(katstr)); %#ok<PROPLC>
                        obj.numelP = zeros(numel(pacienti),size(intervals,1),numel(katstr)+1); %#ok<PROPLC> %tam budu ukladat pocty elektrod pro kazdy interval a pacienta
                        elcount = zeros(size(prumery,2),size(prumery,3)+1); %pocet elektrod pro kazdy casovy interval a kategorii - interval x kategorie
                        P = cell([numel(pacienti),size(prumery,2),size(prumery,3)+1]); % souhrnne prumery pro vsechny pacienty: pacient*interval*kategorie
                        M = cell([numel(pacienti),size(prumery,2),size(prumery,3)+1]); % souhrnne MNI koordinaty pro vsechny pacienty
                        N = cell([numel(pacienti),size(prumery,2),size(prumery,3)+1]); % souhrnne names pro vsechny pacienty
                            %+1 je pro obrazek vsech elektrod i tech bez odpovedi
                    end
                    obj.katstr_pacients(p,:) = katstr; %#ok<PROPLC> %jsou kategorie u vsech pacientu ve stejnem poradi?
                    for interval = 1:size(prumery,2) % cyklus intervaly
                        for kat = 1:size(prumery,3)+1 % cyklus kategorie podnetu
                            if kat <= size(prumery,3) %obvykle kategorie
                                ip = prumery(:,interval, kat) ~= 0; % chci i zaporny rozdil ; aby tam neco bylo 
                                P{p,interval,kat}=prumery(ip,interval, kat); %#ok<AGROW>
                                M{p,interval,kat}=MNI(ip); %#ok<AGROW,PROPLC>>
                                N{p,interval,kat}= strcat(cellstr(repmat([pacienti(p).folder(1:4) '_'],sum(ip),1)),names(ip)); %#ok<AGROW>
                                elcount(interval,kat) = elcount(interval,kat) + sum(ip); %#ok<AGROW>
                                obj.numelP(p,interval,kat)=sum(ip);
                            else %kategorie jakoby navic pro vykresleni jen pozice elekrod
                                channels = size(prumery,1);
                                P{p,interval,kat}=zeros(channels,1); %#ok<AGROW> % 0 pro kazdy kanal - vsechny stejnou barvou
                                M{p,interval,kat}=MNI; %#ok<AGROW,PROPLC>>
                                N{p,interval,kat}= strcat(cellstr(repmat([pacienti(p).folder(1:4) '_'],channels,1)),names); %#ok<AGROW>
                                elcount(interval,kat) = elcount(interval,kat) + channels; %#ok<AGROW>                                
                                obj.numelP(p,interval,kat)=channels;
                            end
                        end                       
                    end 
                end
            end
            %ted z P M a N rozdelenych po pacientech udelam souhrnna data
            obj.VALS = cell(size(elcount)); %souhrnne prumery - interval * kategorie
            obj.MNI = cell(size(elcount)); 
            obj.NAMES = cell(size(elcount));       
            if sum([pacienti.todo])>0 
                for interval = 1:size(prumery,2) 
                    for kat = 1:size(prumery,3)+1                   
                          obj.VALS{interval,kat} = zeros(elcount(interval,kat),1);
                          obj.MNI{interval,kat} = struct('MNI_x',{},'MNI_y',{},'MNI_z',{});
                          obj.NAMES{interval,kat} = cell(elcount(interval,kat),1);
                          iVALS = 1;
                          for p = 1:numel(pacienti) 
                              if pacienti(p).todo
                                  n = numel(P{p,interval,kat});
                                  obj.VALS{interval,kat} (iVALS:iVALS+n-1)=P{p,interval,kat};
                                  obj.MNI{interval,kat}  (iVALS:iVALS+n-1)=M{p,interval,kat};
                                  obj.NAMES{interval,kat}(iVALS:iVALS+n-1)=N{p,interval,kat};
                                  iVALS = iVALS + n;
                              end
                          end
                    end
                end             
                disp(''); %prazdna radka
                %disp(['vytvoreny ' num2str(numel(obj.katstr)) ' kategorie: ' cell2str(obj.katstr)]);
                %jeste vypisu pocty elektrod pro kazdou kategorii
                fprintf('\npocty elektrod v %i kategoriich (pro vsechny pacienty):\n',numel(obj.katstr));
                for kat = 1:numel(obj.katstr)
                    fprintf('%s:\t', obj.katstr{kat});
                    for int = 1:size(intervals,1)
                        fprintf(' %i,', sum(obj.numelP(:,int,kat)));
                    end
                    fprintf('\n');
                end               
            else
                disp('zadny soubor nenalezen');
            end
        end
        function [obj] = GetPAC(obj,prumery,H,pac_folder)
            if isempty(obj.PAC)
                obj.PAC = cell(size(prumery,2),size(prumery,3));
                obj.iPAC = ones(size(prumery,2),size(prumery,3));
            end
            for interval = 1:size(prumery,2)
                for kat = 1:size(prumery,3)
                    if obj.iPAC(interval,kat) == 1
                        obj.PAC{interval,kat} = {};
                    end                    
                    index = find(prumery(:,interval,kat)~=0);
                    for ii = 1:numel(index)                
                        obj.PAC{interval,kat}(obj.iPAC(interval,kat)).pacient = pac_folder; %#ok<AGROW>
                        obj.PAC{interval,kat}(obj.iPAC(interval,kat)).ch = index(ii); %#ok<AGROW>
                        obj.PAC{interval,kat}(obj.iPAC(interval,kat)).name = H.channels(index(ii)).name; %#ok<AGROW>
                        obj.PAC{interval,kat}(obj.iPAC(interval,kat)).neurologyLabel = H.channels(index(ii)).neurologyLabel; %#ok<AGROW>
                        obj.PAC{interval,kat}(obj.iPAC(interval,kat)).ass_brainAtlas = H.channels(index(ii)).ass_brainAtlas;%#ok<AGROW>
                        obj.PAC{interval,kat}(obj.iPAC(interval,kat)).ass_cytoarchMap = H.channels(index(ii)).ass_cytoarchMap; %#ok<AGROW>
                        obj.iPAC(interval,kat) = obj.iPAC(interval,kat) + 1;
                    end
                end
            end
        end
        function obj = ImportData(obj,BPD)
            %vlozi data, ktera jsem vytvoril pomoci CHilbert.ExtractBrainPlotData
            obj.VALS = BPD.VALS;
            obj.MNI = BPD.MNI;
            obj.NAMES = BPD.NAMES;
            obj.katstr = BPD.katstr;
            obj.intervals = BPD.intervals;       
            obj.testname = BPD.testname;
            obj.reference = BPD.reference;
            obj.Hf = BPD.Hf;
        end
        function PlotBrain3D(obj,kategorie,signum,outputDir,overwrite)
            %vykresli jpg obrazky jednotlivych kategorii a kontrastu mezi nimi            
            %TODO do jmena vystupniho jpg pridat i frekvence a referenci, aby se to neprepisovalo
            %TODO je mozne ty signif vyexportovat a pak je nacist zase do CHilbertMulti?
            %TODO do vystupni tabulky nejak dostat anatomickou lokalizaci?
            assert(~isempty(obj.VALS),'zadna data VALS');
            plotSetup = {};
            if ~exist('kategorie','var') || isempty(kategorie) , kategorie = 1:size(obj.VALS,2); end %muzu chtit jen nektere kategorie
            if ~exist('signum','var') || isempty(signum), signum = 0; end; %defaultni je rozdil kladny i zaporny
            if ~exist('outputDir','var') || isempty(outputDir)
                plotSetup.outputDir = 'd:\eeg\motol\CBrainPlot\';    
            else
                plotSetup.outputDir = outputDir;
            end            
            if ~exist('overwrite','var'), overwrite = 1; end; %defaultne se vystupni soubory prepisuji
            
            if ~isempty(obj.brainsurface)
                brainsurface = obj.brainsurface;  %#ok<PROPLC>
            else
                brainsurface = []; %#ok<PROPLC>
            end
            hybernovat = 0; %jestli chci po konci skriptu pocitac uspat - ma prednost
            vypnout = 0;  %jestli chci po konci skriptu pocitac vypnout (a nechci ho hybernovat)             
            plotSetup.figureVisible = 'off';   %nechci zobrazovat obrazek 
            plotSetup.FontSize = 4; 
            plotSetup.myColorMap = iff(signum ~= 0,parula(128) ,jet(128));    %pokud jednostrane rozdily, chci parula
            tablelog = cell(obj.pocetcykluPlot3D(kategorie,signum)+2,5); % z toho bude vystupni xls tabulka s prehledem vysledku
            tablelog(1,:) = {datestr(now),obj.filename,'','',''}; %hlavicky xls tabulky
            tablelog(2,:) = {'interval','kategorie','chname','mni','val'}; %hlavicky xls tabulky
            iTL = 2; %index v tablelog
            tic; %zadnu merit cas
            for interval = 1:size(obj.VALS,1) 
                for kat = kategorie
                    if signum > 0 
                        iV = obj.VALS{interval,kat} > 0; %jen kladne rozdily
                    elseif signum <0 
                        iV = obj.VALS{interval,kat} < 0; %jen zaporne rozdily
                    else
                        iV = true(size(obj.VALS{interval,kat})); %vsechny rozdily
                    end                    
%                
                    katname = obj.katstr{kat};
                    plotSetup.circle_size = iff(strcmp(katname,'all') || strcmp(katname,'AllEl'),28,56); %mensi kulicka pokud vsechny elektrody                
                    
                    if strcmp(plotSetup.figureVisible,'off')
                        disp('figures invisible');
                    end
                    plotSetup.figureNamePrefix = [ obj.testname '_' mat2str(obj.intervals(interval,:))  '_' katname '_' num2str(signum) ...
                            '_' num2str(obj.Hf(1)) '-' num2str(obj.Hf(end)) '_' obj.reference '_NOnames'];
                    if numel(obj.VALS{interval,kat}(iV)) > 0 && (isempty(dir([ plotSetup.outputDir '3D_model\' plotSetup.figureNamePrefix '*'])) || overwrite==1 )
                        disp(plotSetup.figureNamePrefix);
                        
                        vals_channels = obj.VALS{interval,kat}(iV); %parametr  main_brainPlot
                        if signum ~= 0
                            vals_channels = vals_channels*signum; %u zapornych hodnot prehodim znamenko
                        end
                        mni_channels = obj.MNI{interval,kat}(iV);                                                                         
                        names_channels = []; 
                         
                        if ~strcmp(obj.katstr{kat},'AllEl') %nechci to pro kategorii vsech elektrod
                            for iV = 1:numel(vals_channels)
                                tablelog(iV + iTL,:) = { sprintf('[%.1f %.1f]',obj.intervals(interval,:)),obj.katstr{kat}, obj.NAMES{interval,kat}{iV}, ...
                                    sprintf('[%.1f,%.1f,%.1f]',mni_channels(iV).MNI_x, mni_channels(iV).MNI_y, mni_channels(iV).MNI_z), vals_channels(iV)};
                            end
                            iTL = iTL + numel(vals_channels);
                        end
                        
                        %nejdriv vykreslim bez popisku elektrod
                        brainsurface = main_brainPlot(vals_channels,mni_channels,names_channels,brainsurface,plotSetup);  %#ok<PROPLC>
                        %volam Jirkuv skript, vsechny ty promenne predtim jsou do nej
                        if isempty(obj.brainsurface)
                            obj.brainsurface = brainsurface; %#ok<PROPLC> %ulozim si ho pro dalsi volani
                        end
                        
                        %a pak jeste s popisy elektrod                        
                        plotSetup.figureNamePrefix = [ obj.testname '_' mat2str(obj.intervals(interval,:))  '_' katname '_' num2str(signum) ...
                            '_' num2str(obj.Hf(1)) '-' num2str(obj.Hf(end)) '_' obj.reference '_names'];
                        disp(plotSetup.figureNamePrefix);
                        names_channels = obj.NAMES{interval,kat};                         
                        brainsurface = main_brainPlot(vals_channels,mni_channels,names_channels,brainsurface,plotSetup);    %#ok<PROPLC>  
                    elseif  numel(obj.VALS{interval,kat}(iV)) == 0  
                        disp(['zadne hodnoty pro ' plotSetup.figureNamePrefix ' - neukladam ']);
                    else
                        disp(['soubor uz existuje ' plotSetup.figureNamePrefix ' - neprepisuju ']);
                    end
                end
            end
            toc; %ukoncim mereni casu a vypisu
            logfilename = ['logs\PlotBrain3D_' obj.testname '_' datestr(now, 'yyyy-mm-dd_HH-MM-SS') ];
            xlswrite([plotSetup.outputDir logfilename '.xls'],tablelog); %zapisu do xls tabulky
            if hybernovat
                system('shutdown -h')  %#ok<UNRCH>
            elseif vypnout            
                system('shutdown -s') %#ok<UNRCH>
            end
        end
    end
    methods (Static,Access = public)
        function PAC = StructFind(struktura,label,testname,reference)
            %najde pacienty, jejich headery obsahuji mozkovou strukturu
            %struktura je nazev struktury podle atlas napriklad hippo, label je kratky nazev podle martina, napriklad hi
            if ~exist('label','var'),    label = struktura; end %defaultni test
            if ~exist('testname','var') || isempty(testname), testname = 'aedist'; end %defaultni test
            if ~exist('reference','var') || isempty(reference), reference = []; end %defaultni test
            if ischar(struktura), struktura = {struktura}; end %prevedu na cell array
            if ischar(label), label = {label}; end %prevedu na cell array
            [ pacienti, setup ] = pacienti_setup_load( testname );
            PAC = {};
            iPAC = 1;
            for p = 1:numel(pacienti)
                disp(['* ' pacienti(p).folder ' - ' pacienti(p).header ' *']);
                hfilename = [setup.basedir pacienti(p).folder '\' pacienti(p).header];                
                if exist(hfilename,'file')==2
                    load(hfilename);
                else
                    disp(['header ' hfilename ' neexistuje']);
                    continue; %zkusim dalsiho pacienta, abych vypsal, ktere vsechny headery neexistujou
                end               
                if ~isempty(reference)
                    CH = CHHeader(H);
                    CH.RejectChannels( pacienti(p).rjch); %musim vyradit vyrazene kanaly, protoze ty se vyrazuji v bipolarni referenci
                    CH.ChangeReference(reference); %nove od 18.1.2018
                    H = CH.H;
                end
                ii = ~cellfun(@isempty,{H.channels.neurologyLabel}); %neprazdne cells
                index = [];
                labels = lower({H.channels(ii).neurologyLabel}');
                for jj = 1:size(label,2)                    
                    indexjj =  find(~cellfun('isempty',strfind(labels,lower(label{jj}))))'; %rozepsal jsem, aby se to dalo lepe debugovat
                    index = [index indexjj];  %#ok<AGROW>
                    % 3.5.2018 nejakym zahadnym zpusobem funguje hledani pomoci strfind ve sloupci a ne v radku. 
                    % Proto nejdriv prehodim pomoci ' na sloupec a pak zase na radek
                end
                iiBA = ~cellfun(@isempty,{H.channels.ass_brainAtlas}); %neprazdne cells
                iiCM = ~cellfun(@isempty,{H.channels.ass_cytoarchMap}); %neprazdne cells
                for jj = 1:size(struktura,2)
                    index = [ index find(~cellfun('isempty',strfind(lower({H.channels(iiCM).ass_cytoarchMap}),lower(struktura{jj}))))]; %#ok<AGROW>
                    index = [ index find(~cellfun('isempty',strfind(lower({H.channels(iiBA).ass_brainAtlas}),lower(struktura{jj}))))]; %#ok<AGROW>
                end
                index = union(index,[]); %vsechny tri dohromady
                if isempty(reference) || reference ~= 'b' %pokud jsem kanaly nevyradil uz pri zmene reference - vyrazuji se jen pri bipolarni
                    indexvyradit = ismember(index, pacienti(p).rjch); %vyrazene kanaly tady nechci
                    index(indexvyradit)=[]; 
                end
                
                %vrati indexy radku ze struct array, ktere obsahuji v sloupci neurologyLabel substring struktura
                for ii = 1:numel(index)                
                    PAC(iPAC).pacient = pacienti(p).folder; %#ok<AGROW>
                    PAC(iPAC).ch = index(ii); %#ok<AGROW>
                    PAC(iPAC).name = H.channels(index(ii)).name; %#ok<AGROW>
                    PAC(iPAC).neurologyLabel = H.channels(index(ii)).neurologyLabel; %#ok<AGROW>
                    PAC(iPAC).ass_brainAtlas = H.channels(index(ii)).ass_brainAtlas;%#ok<AGROW>
                    PAC(iPAC).ass_cytoarchMap = H.channels(index(ii)).ass_cytoarchMap; %#ok<AGROW>
                    iPAC = iPAC + 1;
                end
            end            
        end
        function PAC = StructFindLoad(xlsfile,sheet)
            %nacteni struktury PAC z existujiciho xls souboru, napr po editaci radku            
             if ~exist('sheet','var'), sheet = 1; end %defaultni je prvni list
             [~ ,~ , raw]=xlsread(xlsfile,sheet); 
             for iraw = 1:numel(raw)
                 if(~isnumeric(raw{iraw}))
                     raw{iraw} = strrep(raw{iraw},'''',''); %neprisel jsem na zpusob, jak o udelat hromadne, isnumeric nefunguje na cely cellarray
                     %mozna by to slo po sloupcich, to ted neresim
                 end
             end
             PAC = cell2struct(raw(2:end,:),raw(1,:),2)';  %originalni PAC struktura z StructFind ma rozmer 1 x N, takze transponuju z excelu
             disp( [ basename(xlsfile) ': soubor nacten']);
        end
        function MIS = StructFindErr(testname)
            [ pacienti, setup ] = pacienti_setup_load( testname );
            load('BrainAtlas_zkratky.mat');
            MIS = {}; %pacient, ch, zkratka-  z toho bude vystupni xls tabulka s prehledem vysledku            
            iMIS = 1;
            for p = 1:numel(pacienti)
                disp(['* ' pacienti(p).folder ' - ' pacienti(p).header ' *']);
                hfilename = [setup.basedir pacienti(p).folder '\' pacienti(p).header];                
                if exist(hfilename,'file')==2
                    load(hfilename);
                else
                    disp(['header ' hfilename ' neexistuje']);
                    continue; %zkusim dalsiho pacienta, abych vypsal, ktere vsechny headery neexistujou
                end  
                for ch = 1:numel(H.channels)
                    z = strsplit(H.channels(ch).neurologyLabel,{'/','(',')'});
                    for iz = 1:numel(z)
                        if isempty(find(~cellfun('isempty',strfind(lower(BrainAtlas_zkratky(:,1)),lower(z{iz}))), 1)) %#ok<NODEF>
                           MIS(iMIS).pac = pacienti(p).folder; %#ok<AGROW>
                           MIS(iMIS).ch = ch; %#ok<AGROW>
                           MIS(iMIS).neurologyLabel = H.channels(ch).neurologyLabel; %#ok<AGROW>
                           MIS(iMIS).label = z{iz}; %#ok<AGROW>
                           MIS(iMIS).brainAtlas = H.channels(ch).ass_brainAtlas; %#ok<AGROW>
                           MIS(iMIS).cytoarchMap = H.channels(ch).ass_cytoarchMap; %#ok<AGROW>
                           iMIS = iMIS+ 1;
                        end
                    end
                end
            end
        end
    end
    methods (Access=private)
        function n = pocetcykluPlot3D(obj,kategorie,signum)
            %spocita kolik kanalu celkem vykresli PlotBrain3D pro tyto parametry
            n = 0; 
            for interval = 1:size(obj.VALS,1)  
                for kat = kategorie
                    if ~strcmp(obj.katstr{kat},'AllEl') %nechci to pro kategorii vsech elektrod
                        if signum > 0 
                            iV = obj.VALS{interval,kat} > 0; %jen kladne rozdily
                        elseif signum <0 
                            iV = obj.VALS{interval,kat} < 0; %jen zaporne rozdily
                        else
                            iV = true(size(obj.VALS{interval,kat})); %vsechny rozdily
                        end
                        n = n + numel(obj.VALS{interval,kat}(iV));
                    end
                end
            end
        end
    end
    
end

