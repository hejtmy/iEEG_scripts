classdef ScatterPlot < handle
    %SCATTERPLOT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        ieegdata@CiEEGData; % handle na zdroj dat
        header; % handle na kopii ieegdata.CH, kvuli PlotBrain
        dispChannels; % zobrazene kanaly v grafu
        dispData; % vyobrazena data ve scatterplotu
        
        stats; % spocitane statistiky
        
        is3D;   % urcuje, zda se jedna o 3D plot
        
        selCh ; % kopie ieegdata.plotRCh.selCh;
        selChNames ; % kopie ieegdata.plotRCh.selChNames
        dispSelCh % vyber klavesami fghjkl - the channel numbers
        dispSelChN % logical index of channels marks 1-6 displayed
        dispSelChName %names of channel marks fghjkl displayd
        
        dispFilterCh % CH.sortorder
        
        connectChannels;    % urcuje, zda se maji propojit stejne kanaly pro ruzne podnety
        connectionsPlot;    % handle na plot se spojnicemi mezi kanaly
        
        fig;    % handle na hlavni figure scatter plotu
        ax;     % handle na osy patrici k fig
        plots;  % vsechny vykreslene plty
        sbox;   % handle na info text s vybranym kanalem
        pbox;   % handle na info text s vybranymi kategoriemi
        texthandles;  % handle na texty v obrazku, abych je mohl smazat
        
        highlights; % handle na plot se zvyraznenim vybraneho kanalu
        
        showNumbers; % zobrazit popisky hodnot, 0=nic 1=cisla 2=jmena kanalu
        numbers;    % handle na zobrazene popisky hodnot
        markerSize; % velikost markery ve scatter plotu
        
        axisX@char;  % strin identifikujici typ dat na osach x,y,z
        axisY@char;  % nastavuje se pri inicializaci scatter plotu (initAxes)
        axisZ@char;  % pro mozne hodnoty viz funkci initAxes
        
        valFraction@double;    % podil z maximalni hodnoty pro trigger tfrac
        intFraction@double;    % podil z maximalni hodnoty pro trigger tint
        
        categories %seznam cisel kategorii od nejdulezitejsi (podle poradi ve statistice)
        categoryNames %jmena kategorii odpovidajici obj.categories
        categoriesSelectionIndex %aktualne zobrazene kategorie, na zacatku 1:numel(obj.categories)

        filterListener;  % reaguje na zmenu filtru pres CH.FilterChannels
        channelListener;    % reaguje na zmenu zvyraznenho kanalu
        
        baseColors = [0 1 0; 0 0 1; 1 0 0; 0 0.8 0.8; 1 0 1; 0 1 0]; % zakladni barvy pro ruzne kategorie
        categoryMarkers = {'o', 's', 'd', 'p'}; % markery pro kategorie
        transparent; % jestli maji byt markers nakreslene s pruhlednosti
    end
    
    methods
        function obj = ScatterPlot(ieegdata, is3D, axisX, axisY, axisZ)
            %SCATTERPLOT Vytvori novy ScatterPlot
            %   is3D urcuje zda se jedna o 2D nebo 3D graf
            %   parametry axis* urcuji typ dat zobrazeny na osach
            obj.ieegdata = ieegdata;
            obj.header = copy(obj.ieegdata.CH); %vytvorim nezavislou kopii kvuli PlotBrain, aby ne kolize z AUCPlotM grafem
            obj.selCh = ieegdata.plotRCh.selCh; %vyber kanalu fghjkl * pocet kanalu
            obj.selChNames = ieegdata.plotRCh.selChNames; %vyber kanalu fghjkl * pocet kanalu
            obj.dispSelChName = [];
            obj.dispSelCh = 1:size(obj.selCh,1);  % Show all channels (all markings)
            obj.dispSelChN = [1 1 1 1 1 1]; %all 6 markings
            
            obj.dispFilterCh = obj.ieegdata.CH.sortorder; % Vyber podle FilterChannels
            obj.connectChannels = 0;
            obj.showNumbers = 0; %defaultne se zadne labels nezobrazuji
            obj.numbers = [];
            obj.markerSize = 34;
            obj.transparent = false;
            
            if ~exist('is3D','var')
                obj.is3D = false; 
            else
                obj.is3D = is3D;
            end
            if ~exist('axisX', 'var')
                obj.axisX = 'tmax';
            else
                obj.axisX = axisX;
            end
            if ~exist('axisY', 'var')
                obj.axisY = 'valmax';
            else
                obj.axisY = axisY;
            end
            if ~exist('axisZ', 'var')
                obj.axisZ = 'category';
            else
                obj.axisZ = axisZ;
            end
            
            obj.setCategories();
            
            obj.drawScatterPlot(0.5, 0.5);
        end
        
        function drawScatterPlot(obj, valFraction, intFraction)
            obj.setTriggerValues(valFraction, intFraction);
            obj.initAxes();
            obj.updatePlot();
            obj.fixAxesLimits();
        end
        
        function PlotBrain(obj,katnum,xy,rangeZ)
            if ~exist('katnum','var') || isempty(katnum), katnum = 1; end %katnum is the kategory num, which should correspond to channel marking 1-3(4)
            if ~exist('xy','var'), xy = 'y'; end %defaultne osaY = valmax napriklad
            if ~exist('rangeZ','var') %pokud neni zadane
                rangeZ = iff(xy=='x',xlim(obj.ax),ylim(obj.ax));  %set by scatter plot y and x limits
            end 
            selChFiltered = obj.selCh(obj.dispChannels,:); %chci zobrazovat jen signif odpovedi
            iselChFiltered = logical(selChFiltered(:,katnum)); %channels with this marking=category
            data = nan(1,size(iselChFiltered,1));
            if(xy=='x')
                for ik = 1:numel(katnum)
                    idata = iselChFiltered(:,ik);
                    data(idata) = nanmax([data(idata);obj.dispData(katnum(ik)).dataX(idata)],[],1);
                end
                dataName = obj.axisX;
            else
                for ik = 1:numel(katnum)
                    idata = iselChFiltered(:,ik); %index of channels with markings 
                    data(idata) = nanmax([data(idata);obj.dispData(katnum(ik)).dataY(idata)],[],1);
                end                
                dataName = obj.axisY;
            end
            idata = ~isnan(data); %exclude data with no significance relative to baseline (in any category)
            obj.header.channelPlot.plotCh3D.selch = []; %nechci mit vybrany zadny kanal z minula
            if isfield(obj.header.plotCh2D,'chshowstr')
                chshowstr = obj.header.plotCh2D.chshowstr; 
            else
                chshowstr = '';
            end
            obj.header.ChannelPlotProxy(data(idata),... %param chnvals
                obj.dispChannels(idata),... %chnsel jsou cisla kanalu, pokud chci jen jejich vyber
                [],[],{[dataName '(' obj.categoryNames{katnum} '), SelCh: ' cell2str(obj.dispSelChName) ], ... %popis grafu = title - prvni radek
                ['show:' chshowstr]}, ... %popis grafu title, druhy radek
                rangeZ); %rozsah hodnot - meritko barevne skaly
            set(obj.header.channelPlot.plotCh3D.fh, 'WindowButtonDownFcn', @obj.hybejPlot3Dclick);
        end
        
        function setXYLim(obj,xrange,yrange) %set axes limit
            if ~exist('xrange','var') || isempty(xrange), xrange = xlim(obj.ax); end
            if ~exist('yrange','var') || isempty(yrange), yrange = ylim(obj.ax); end
            xlim(obj.ax,xrange);
            ylim(obj.ax,yrange);
        end
        
        function CopyChannelPlot3DROI(obj)
            %copies ROI from ChannelPlot3D figure from ScatterPlot object to original CHilbertMulti object
            %to be saved with the CM object and not deleted with the SP object
            obj.ieegdata.CH.plotCh3D.roi = obj.header.plotCh3D.roi ;
            disp( [num2str(size(obj.header.plotCh3D.roi,1)) ' ROIs copied']);
        end

    end

    methods(Access = private)
        
        function setCategories(obj)
            if ~isempty(obj.ieegdata.Wp) && isfield(obj.ieegdata.Wp(obj.ieegdata.WpActive), 'kats') %prvni volba je pouzit kategorie ze statistiky
                obj.categories  = flip(obj.ieegdata.Wp(obj.ieegdata.WpActive).kats);
            else
                obj.categories = obj.ieegdata.PsyData.Categories(); %pokud nejsou, pouziju vsechny kategorie
            end
            obj.categoryNames = strings(size(obj.categories));
            for k = 1 : numel(obj.categories)                
                catnum = cellval(obj.categories,k);%cislo kategorie, muze byt cell, pokud vice kategorii proti jedne
                obj.categoryNames(k) = obj.ieegdata.PsyData.CategoryName(catnum);
            end
            obj.categoriesSelectionIndex = 1:numel(obj.categories);
        end
 
        function initAxes(obj)
            axesSelection = {obj.axisX, obj.axisY, obj.axisZ}; % pozadovane parametry na vsech osach
            axesLabels = cell(1,3); % nazvy vsech os
            for i=1:3   % projdu vsechny osy a nastavim jejich label
                switch axesSelection{i}
                    case 'valmax'
                        axesLabels{i} = 'v_{max}';
                    case 'tmax'
                        axesLabels{i} = 't_{max}';
                    case 'tfrac'
                        axesLabels{i} = ['t_{' num2str(obj.valFraction) '}'];
                    case 'tint'
                        axesLabels{i} =  ['t_{int, ' num2str(obj.intFraction) '}'];
                    case 'channel'
                        axesLabels{i} = 'channel';
                    case 'category'
                        axesLabels{i} = 'category';
                    case 'mnix'
                        axesLabels{i} = 'MNI_x';
                    case 'mniy'
                        axesLabels{i} = 'MNI_y';
                    case 'mniz'
                        axesLabels{i} = 'MNI_z';
                    otherwise
                        disp('Axis specification must be one of: valmax, tmax, tfrac, tint, channel, category, mnix, mniy, mniz');
                        return;
                end
            end
            
            obj.fig = figure('CloseRequestFcn', @obj.tearDownFigCallback, 'Name', 'ScatterPlot');
            
            obj.ax = axes(obj.fig);
            xlabel(obj.ax, axesLabels{1});
            ylabel(obj.ax, axesLabels{2});
            zlabel(obj.ax, axesLabels{3});

            obj.filterListener = addlistener(obj.ieegdata.CH, 'FilterChanged', @obj.filterChangedCallback);
            obj.channelListener = addlistener(obj.ieegdata, 'SelectedChannel', 'PostSet', @obj.channelChangedCallback);
            
            set(obj.fig, 'KeyPressFcn', @obj.hybejScatterPlot);
            set(obj.fig, 'WindowButtonDownFcn', @obj.hybejScatterPlotClick);
        end
        
        function setTriggerValues(obj, valFraction, intFraction)
            obj.valFraction = valFraction;
            obj.intFraction = intFraction;
        end
        
        function fixAxesLimits(obj)
            xlim(xlim(obj.ax));
            ylim(ylim(obj.ax));
        end
        
        function updatePlot(obj,recompute)
            if ~exist('recompute','var'), recompute = 1; end
            obj.setDisplayedChannels(); % Kombinace voleb pro zobrazeni kanalu
            selChFiltered = obj.selCh(obj.dispChannels,:); %channels x marks - filter kanalu ve vyberu fghjkl
            RjCh = intersect(intersect(obj.dispFilterCh, obj.dispSelCh),obj.ieegdata.RjCh); %vyrazene kanaly z tech nyni zobrazenych - cisla kanalu
            selChRj = obj.selCh(RjCh,:); %filter vyrazenych kanalu ve vyberu fghjkl
            delete(obj.plots); obj.plots = [];
            delete(obj.sbox);
            delete(obj.pbox);            
            delete(obj.connectionsPlot); obj.connectionsPlot = [];
            delete(obj.numbers); obj.numbers = [];  
            for j = 1:numel(obj.texthandles)
                if isgraphics(obj.texthandles(j)) && obj.texthandles(j) ~= 0
                    delete(obj.texthandles(j));  
                end
            end            
            obj.texthandles = nan(2,numel(obj.categories)); %kategories in first row, chanel legent in second row
            
            if ~isempty(obj.dispSelChName)
                obj.sbox = annotation(obj.fig, 'textbox',[0 .9 .4 .1], 'String', obj.dispSelChName, 'EdgeColor', 'none');
            end
            
            catlist = strjoin(obj.categoryNames(obj.categoriesSelectionIndex), ', ');
            obj.pbox = annotation(obj.fig, 'textbox', [0 0 .4 .1], 'String', ['C: ' catlist], 'EdgeColor', 'none');
            
           
            if isempty(obj.dispChannels)
                disp('No channels corresponding to the selection');
                return;
            end
            if recompute
                obj.stats = struct();
                for k = obj.categoriesSelectionIndex %1:numel(obj.categories)
                    catnum = obj.categories(k);
                    [obj.stats(k).valmax, obj.stats(k).tmax, obj.stats(k).tfrac, obj.stats(k).tint] = obj.ieegdata.ResponseTriggerTime(obj.valFraction, obj.intFraction, catnum, obj.dispChannels);
                end
            end
            
            hold(obj.ax, 'on');
            legend(obj.ax, 'off');
            
            if obj.connectChannels > 0
                obj.drawConnectChannels();
            end
            obj.drawPlot(selChFiltered, selChRj);
            
            legend(obj.ax, 'show');
            hold(obj.ax, 'off');
            if isfield(obj.ieegdata.CH.plotCh2D, 'chshowstr') && ~isempty(obj.ieegdata.CH.plotCh2D.chshowstr)
                title(['show:' obj.ieegdata.CH.plotCh2D.chshowstr]);
            else
                title('show: all');
            end
            
            if obj.is3D
                grid(obj.ax, 'on');
            else
                grid(obj.ax, 'off');
            end
        end
        
        function data = getData(obj, dataType, categoryIndex)
        % getData vraci data pro jednu osu.
        %       dataType je druh pozadovanych dat (viz initAxes)
        %       categoryIndex je index aktualni kategorie
            numChannels = size(obj.dispChannels); % Pocet zobrazenych kanalu
            switch dataType
                case 'channel'
                    data = obj.dispChannels;
                case 'category'
                    data = categoryIndex * ones(numChannels);
                case 'mnix'
                    data = [obj.ieegdata.CH.H.channels(obj.dispChannels).MNI_x];
                case 'mniy'
                    data = [obj.ieegdata.CH.H.channels(obj.dispChannels).MNI_y];
                case 'mniz'
                    data = [obj.ieegdata.CH.H.channels(obj.dispChannels).MNI_z];
                otherwise
                    data = obj.stats(categoryIndex).(dataType);
            end
        end
        
        function drawPlot(obj, selChFiltered, selChRj)
            pocty = zeros(max(obj.categoriesSelectionIndex),3); % maximalni mozny index zobrazeneho kanalu
            for k = flip(obj.categoriesSelectionIndex) %nejpozdeji, cili nejvic na vrchu, chci mit prvni kategorii %1:numel(obj.categories)
                dataX = obj.getData(obj.axisX, k);
                dataY = obj.getData(obj.axisY, k);
                if obj.is3D
                    dataZ = obj.getData(obj.axisZ, k);
                end
                
                iData = logical(selChFiltered(:,k)); %kanaly se signifikantim rozdilem vuci baseline v teto kategorii
                if any(iData)
                    if obj.is3D
                        obj.plots(k,1) = scatter3(obj.ax, dataX(iData), dataY(iData), dataZ(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'flat', 'DisplayName', obj.categoryNames{k});
                        if obj.transparent, alpha(obj.plots(k,1),.5); end %volitelne pridani pruhlednosti
                    else
                        obj.plots(k,1) = scatter(obj.ax, dataX(iData), dataY(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'flat', 'DisplayName', obj.categoryNames{k});
                        if obj.transparent, alpha(obj.plots(k,1),.5); end %volitelne pridani pruhlednosti
                    end
                    pocty(k,1) = sum(iData); %pocet signifikantnich v teto kategorii
                end
                iData = ~iData; %kanaly bez signif rozdilu vuci baseline v teto kategorii
                if any(iData) && obj.connectChannels >= 0
                    if ~any(~iData) % Pokud zadny kanal nemel signif. rozdil, nevytvoril se pro nej graf, ani legenda
                        handleVisibility = 'on';    % Zobrazime legendu z grafu bez signif. rozdilu
                    else
                        handleVisibility = 'off';   % Pokud signif. rozdil mel, jeden graf uz se vytvoril i s legendu, takze nebudeme zobrazovat dalsi
                    end
                    if obj.is3D
                        obj.plots(k,2) = scatter3(obj.ax, dataX(iData), dataY(iData), dataZ(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'none', 'DisplayName', obj.categoryNames{k},...
                            'HandleVisibility', handleVisibility);
                    else
                        obj.plots(k,2) = scatter(obj.ax, dataX(iData), dataY(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'none', 'DisplayName', obj.categoryNames{k},...
                            'HandleVisibility', handleVisibility);
                    end
                    pocty(k,2) = sum(iData); %pocet ne signifikantnich v teto kategorii
                end
                if any(logical(selChRj(:,k))) %pocet rejectovanych pro tuto kategorii
                    pocty(k,3) = sum(logical(selChRj(:,k))); 
                end
                if obj.showNumbers > 0 %pojmenovani bodu ve scatterplotu
                    switch obj.showNumbers
                        case 1
                            labels = cellstr(num2str(obj.dispChannels')); %cisla zobrazenych kanalu 
                        case 2
                            labels = {obj.ieegdata.CH.H.channels(obj.dispChannels).name}'; %jmena kanalu
                        case 3
                            labels = {obj.ieegdata.CH.H.channels(obj.dispChannels).neurologyLabel}'; %anatomicke oznaceni kanalu
                        case 4
                            if isa(obj.ieegdata, 'CHilbertMulti')
                                names = {obj.ieegdata.CH.H.channels(obj.dispChannels).name}; % jmena pacientu
                                labels = cellstr(extractBefore(names,' ')); %vsechno pred mezerou - pro CHilbertMulti
                            else
                                labels = cellstr(num2str(obj.dispChannels'));
                                disp('Cannot show paient names, iEEG data not a CHilbertMulti object');
                            end
                    end
                    dx = diff(xlim)/100;
                    iData = iff( obj.connectChannels >= 0 , true(size(selChFiltered,1),1), logical(selChFiltered(:,k)) ); %jestli zobrazit vsechny labels, nebo jen signifikantni
                    if obj.is3D
                        th = text(dataX(iData)+dx, dataY(iData), obj.dispChannels(iData), labels(iData), 'FontSize', 8);
                    else
                        th = text(dataX(iData)+dx, dataY(iData), labels(iData), 'FontSize', 8);
                    end
                    set(th, 'Clipping', 'on');
                    obj.numbers = [obj.numbers ; th]; % do dlouheho sloupce, kazda kategorie ma ruzny pocet zobrazenych kanalu a textu
                end
                obj.dispData(k).dataX = dataX; %zalohuju vyobrazena data pro jine pouziti
                obj.dispData(k).dataY = dataY;
                
                xsize = xlim(obj.ax); ysize = ylim(obj.ax);
                xtext = xsize(2)-diff(xsize)/5;
                ytext = ysize(2)-diff(ysize)/5;
                
                obj.texthandles(1,k) = text(xtext, ytext - (k-1)*diff(ysize)/20 ,[obj.categoryNames{k} ':' num2str(pocty(k,1)) '+' num2str(pocty(k,2)) ' (' num2str(pocty(k,3)) ')' ]);
            end
        end
        
        function drawConnectChannels(obj)
        % Nakresli linku spojujici stejne kanaly. Ruzne barvy musi byt samostatny plot (aby mohl scatter zustat ve stejnych osach)
            if length(obj.categoriesSelectionIndex) > 1
                validCategoryIndex = obj.categoriesSelectionIndex(1); % cislo prvni se zobrazenych kategorii - pro inicializaci poli musim znat velikost nejkae jiz spocitane (platne) kategorie
                x = zeros(length(obj.categoriesSelectionIndex), length(obj.getData(obj.axisX, validCategoryIndex)));
                y = zeros(length(obj.categoriesSelectionIndex), length(obj.getData(obj.axisY, validCategoryIndex)));
                if obj.is3D
                    z = zeros(length(obj.categoriesSelectionIndex), length(obj.getData(obj.axisZ, validCategoryIndex)));
                end
                for cat = 1:length(obj.categoriesSelectionIndex)
                    catIndex = obj.categoriesSelectionIndex(cat); % aktualni kategorie
                    x(cat,:) = obj.getData(obj.axisX, catIndex);
                    y(cat,:) = obj.getData(obj.axisY, catIndex);
                    if obj.is3D
                        z(cat,:) = obj.getData(obj.axisZ, catIndex);
                    end
                end
                l = length(obj.stats(obj.categoriesSelectionIndex(1)).(obj.axisX));
                for k = 1:l
                    xx = [x(:,k); x(1,k)]; %tri body za vsechny kategorie + pridam prvni na konec znovu, aby se spojily
                    yy = [y(:,k); y(1,k)]; %kvuli zrychleni u velkeho mnozstvi bodu
                    if obj.is3D
                        zz = [z(:,k); z(1,k)];
                        
                        %if strcmp(obj.axisZ, 'channel')
                        %    zz = obj.dispChannels(k) * ones(size(xx));
                        %elseif strcmp(obj.axisZ, 'category')
                        %    zz = [obj.categoriesSelectionIndex obj.categoriesSelectionIndex(1)] * ones(1, size(xx,2));
                        %else
                        %    zz = [z(:,k); z(1,k)];
                        %end
                                
                        obj.connectionsPlot(end+1) = plot3(xx, yy, zz, 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
                    else
                        obj.connectionsPlot(end+1) = plot(xx, yy, 'Color', [0.5 0.5 0.5], 'HandleVisibility','off');
                    end
                end
            else
                disp('No categories to connect');
                obj.connectChannels = -1;
            end
        end
                
        function highlightSelected(obj, ch)
            if ~isempty(obj.highlights) 
                if isvalid(obj.highlights)
                    delete(obj.highlights);
                end
            end
            obj.highlights = gobjects();
            idx = find(obj.dispChannels == ch);
            hold(obj.ax, 'on');
            if idx
                for k = obj.categoriesSelectionIndex
                    dataX = obj.getData(obj.axisX, k);
                    dataY = obj.getData(obj.axisY, k);
                    if obj.is3D
                        dataZ = obj.getData(obj.axisZ, k);
                    end
                    
                    if obj.is3D
                        obj.highlights(k) = scatter3(obj.ax, dataX(idx), dataY(idx), dataZ(idx), 3*obj.markerSize, 0.75*obj.baseColors(k,:), 'o', 'MarkerFaceColor', 'none', 'LineWidth', 2, 'HandleVisibility','off');
                    else
                        obj.highlights(k) = scatter(obj.ax, dataX(idx), dataY(idx), 3*obj.markerSize, 0.75*obj.baseColors(k,:), 'o', 'MarkerFaceColor', 'none', 'LineWidth', 2, 'HandleVisibility','off');
                    end
                end
                figure(obj.fig);
                if ~isnan(obj.texthandles(2,1)), delete(obj.texthandles(2,1)); end %delete the previously shown text
                obj.texthandles(2,1) = text(obj.ax.XLim(1)+diff(obj.ax.XLim)/20, obj.ax.YLim(2)-diff(obj.ax.YLim)/20,[ 'ch ' num2str(ch) ', ' obj.ieegdata.CH.H.channels(1,ch).name ]);                
            end
            hold(obj.ax, 'off');
        end
        
        function hybejScatterPlot(obj,~,eventDat)
            switch eventDat.Key
                case {'u','i','o','p'}
                    ik = find('uiop'==eventDat.Key); % index 1-4
                    if ik <= numel(obj.categories)
                        if(ismember(ik, obj.categoriesSelectionIndex))
                            obj.categoriesSelectionIndex = setdiff(obj.categoriesSelectionIndex, ik);
                        else
                            obj.categoriesSelectionIndex = union(obj.categoriesSelectionIndex, ik);
                        end
                    end    
                    obj.updatePlot();
                case {'a'}  % Resset do zakladniho vyberu
                    if sum(obj.dispSelChN) < 6 %if not all channel markings are shown
                        %show all channel markings = all channels in current sortorder
                        obj.dispFilterCh = obj.ieegdata.CH.sortorder; % Vyber podle FilterChannels
                        obj.dispSelCh = 1:size(obj.selCh,1);   % Zrusit vyber dle SelCh - display all channels
                        obj.dispSelChN = [1 1 1 1 1 1]; %all channel markings
                    else
                        %if all channel were already shown, show no channels
                        obj.dispSelChN = [0 0 0 0 0 0];
                        obj.dispSelCh = []; %non channels are shown
                    end
                    obj.dispSelChName = [];
                    obj.updatePlot();
                case {'f','g','h','j','k','l'}
                    obj.dispSelChN = xor('fghjkl'==eventDat.Key,obj.dispSelChN);
                    obj.dispSelCh = find(any(obj.selCh(:,obj.dispSelChN),2)');
                    obj.dispSelChName = cell2str(obj.selChNames(obj.dispSelChN)); %string from all cell fields
                    obj.updatePlot();
                case {'s'}
                    obj.connectChannels = obj.connectChannels + 1;
                    if obj.connectChannels >1,  obj.connectChannels = -1; end
                    obj.updatePlot(0);
                case {'t'}
                    obj.transparent =  ~obj.transparent;
                    if obj.connectChannels >1,  obj.connectChannels = -1; end
                    obj.updatePlot(0); %neprepocitat hodnoty
                case {'n'}
                    obj.showNumbers =  mod(obj.showNumbers + 1, 5); % cykluje cisla od 0 do 4
                    obj.updatePlot(0); %neprepocitat hodnoty
                case {'add'}
                    obj.markerSize = obj.markerSize + 8;
                    obj.updatePlot();
                case {'subtract'}
                    obj.markerSize = max(2, obj.markerSize - 8);
                    obj.updatePlot();
            end
        end
        
        function hybejScatterPlotClick(obj,~,~)
            if isempty(obj.dispChannels) % Pokud nejsou zobrazene zadne kanaly, nedelam nic
              return;
            end

            mousept = get(gca,'currentPoint');
            p1 = mousept(1,:); p2 = mousept(2,:); % souradnice kliknuti v grafu - predni a zadni bod
            chs  = zeros(size(obj.categoriesSelectionIndex));     % kanaly v blikosti kliknuti
            normDist = zeros(size(obj.categoriesSelectionIndex)); % vzdalenost normalizovana na meritko os
            for k = 1:length(obj.categoriesSelectionIndex) % vsechny zobrazene kategorie
              categoryIndex = obj.categoriesSelectionIndex(k);
              dataX = obj.getData(obj.axisX, categoryIndex);
              dataY = obj.getData(obj.axisY, categoryIndex);
              xRange = diff(xlim(obj.ax)); % hledani nejblizsiho bodu probehne az po normalizaci os, jinak je problem u os s vyrazne jinymi meritky
              yRange = diff(ylim(obj.ax));
              if obj.is3D
                  dataZ = obj.getData(obj.axisZ, categoryIndex);
                  zRange = diff(zlim(obj.ax));
                  cNorm = [1/xRange 1/yRange 1/zRange]; % normalizace vsech souradnic
              end
              if obj.is3D
                  coordinates = [dataX./xRange; dataY./yRange; dataZ./zRange]; % souradnice zobrazenych kanalu
                  [chs(k), normDist(k)] = findClosestPoint(cNorm.*p1, cNorm.*p2, coordinates, 0.02);    % najdu kanal nejblize mistu kliknuti
              else
                  x = p1(1); y = p1(2); % souradnice v grafu (ve 2D pouze "predni" bod)
                  [chs(k), normDist(k)] = dsearchn([dataX'./xRange dataY'./yRange], [x/xRange y/yRange]); %najde nejblizsi kanal a vzdalenost k nemu
                  if normDist(k) > mean([yRange xRange])/20 % kliknuti prilis daleko od jakehokoliv bodu
                      chs(k) = 0;
                      normDist(k) = inf;
                  end
              end
            end

            [mindist, k_min] = min(normDist); % vyberu skutecne nejblizsi kanal ze vsech kategorii

            if mindist < inf
              ch = obj.dispChannels(chs(k_min));
              %TODO: Pokud neni otevreny PlotResponseCh, nebude po otevreni znat cislo vybraneho kanalu. Lepsi by bylo pouzit proxy objekt, ktery drzi informaci o vybranem kanalu a v pripade zmeny vyberu posle signal, ktery se tak zpropaguje do vsech plotu, ktere ho potrebuji.
              if isfield(obj.ieegdata.plotRCh, 'fh') && isvalid(obj.ieegdata.plotRCh.fh)  % Zjistim, jeslti je otevreny PlotResponseCh
                  sortChannel = find(obj.ieegdata.CH.sortorder == ch);
                  obj.ieegdata.PlotResponseCh(sortChannel);    % Pokud mam PlotResponseCh, updatuju zobrezene kanaly
                  % Nevolam highlightSelected, protoze ten se zavola diky eventu
                  figure(obj.fig); %kamil - dam do popredi scatter plot
              else
                  obj.highlightInMyPlots(ch);
                  %TODO: Pokud ted manualne otevru PlotResponseCh bez parametru, neuvidim v nem spravny kanal
              end
            else
                obj.highlightInMyPlots(0);   % zrusi vyber
            end
        end
        
        function hybejPlot3Dclick(obj, ~, ~)
            mousept = get(gca,'currentPoint');
            p1 = mousept(1,:); p2 = mousept(2,:); % souradnice kliknuti v grafu - predni a zadni bod
            displayedChannels = obj.header.H.channels(obj.header.channelPlot.plotCh3D.dispChannels); % zobrazene kanaly
            coordinates = [displayedChannels.MNI_x; displayedChannels.MNI_y; displayedChannels.MNI_z];    % souradnice zobrazenych kanalu
            closestChannel = findClosestPoint(p1, p2, coordinates, 2);    % najdu kanal nejblize mistu kliknuti
            if closestChannel
                ch = obj.header.channelPlot.plotCh3D.dispChannels(closestChannel);
                %TODO: Pokud neni otevreny PlotResponseCh, nebude po otevreni znat cislo vybraneho kanalu. Lepsi by bylo pouzit proxy objekt, ktery drzi informaci o vybranem kanalu a v pripade zmeny vyberu posle signal, ktery se tak zpropaguje do vsech plotu, ktere ho potrebuji.
                if isfield(obj.ieegdata.plotRCh, 'fh') && isvalid(obj.ieegdata.plotRCh.fh)  % Zjistim, jeslti je otevreny PlotResponseCh
                  sortChannel = find(obj.ieegdata.CH.sortorder == ch);
                  obj.ieegdata.PlotResponseCh(sortChannel);    %#ok<FNDSB> % Pokud mam PlotResponseCh, updatuju zobrezene kanaly
                  % Nevolam highlightSelected, protoze ten se zavola diky eventu
                else
                  obj.highlightInMyPlots(ch);
                  %TODO: Pokud ted manualne otevru PlotResponseCh bez parametru, neuvidim v nem spranvy kanal
                end
            else
                obj.highlightInMyPlots(0);
            end
            figure(obj.header.channelPlot.plotCh3D.fh);
        end
        
        function setDisplayedChannels(obj)
            obj.dispChannels = intersect(obj.dispFilterCh, obj.dispSelCh); % CH.sortorder (vysledek CH.FilterChannels) & vyber klavesami fghjkl 
            obj.dispChannels = setdiff(obj.dispChannels,obj.ieegdata.RjCh); %kamil 15.10 - vyradim ze zobrazeni vyrazene kanaly
        end
        
        function filterChangedCallback(obj,~,~)
            obj.dispFilterCh = obj.ieegdata.CH.sortorder;   % Zmena vyberu dle filtru
            obj.updatePlot();
        end

        function channelChangedCallback(obj, ~, eventData)
            %!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            %TODO: Pri kliknuti do ScatterPlotu se tohle zavola dvakrat!!! Nejspis problem se skoro-zacyklenim z PlotResponseCh. Sice to navenek funguje spravne, ale dvoji volani je nesmysl.
            obj.highlightInMyPlots(eventData.AffectedObject.SelectedChannel);
            %disp(['change in SP: ' num2str(eventData.AffectedObject.SelectedChannel)]);
        end

        function highlightInMyPlots(obj, ch)    %TODO: Toto nebude potreba, pokud budou vsechny ploty reagovat na signal, misto aby se highlight volal explicitne
            obj.highlightSelected(ch);
            if isfield(obj.header.channelPlot.plotCh3D, 'fh') && isvalid(obj.header.channelPlot.plotCh3D.fh)
                obj.header.channelPlot.highlightChannel(ch);
            end
        end
        
        function tearDownFigCallback(obj,src,~)
            delete(obj.filterListener);
            delete(obj.channelListener);
            delete(src);
        end      
        
    end
    
end

