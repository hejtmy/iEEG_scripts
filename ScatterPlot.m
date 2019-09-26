classdef ScatterPlot < handle
    %SCATTERPLOT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        ieegdata
        dispChannels
        dispData; %vyobrazena data ve scatterplotu
        
        is3D
        
        selCh ; %kopie ieegdata.plotRCh.selCh;
        selChNames ; %kopie ieegdata.plotRCh.selChNames;
        dispSelCh
        dispSelChName
        stats % ulozeny vypocet statistik (TODO: pri inicializaci pocitat vse, a pote uz jen provadet filtrovani)
        
        dispFilterCh
        
        connectChannels
        connectionsPlot
        
        fig
        ax
        plots
        sbox
        pbox
        
        highlights
        
        showNumbers; %zobrazit popisky hodnot, 0=nic 1=cisla 2=jmena kanalu
        numbers
        markerSize
        
        axisX
        axisY
        
        valFraction
        intFraction
        
        categories %seznam cisel kategorii od nejdulezitejsi (podle poradi ve statistice)
        categoryNames %jmena kategorii odpovidajici obj.categories
        categoriesSelectionIndex %1:numel(obj.categories)
        
        filterListener
        channelListener
        
        baseColors = [0 1 0; 0 0 1; 1 0 0; 1 1 0; 1 0 1; 0 1 0];
        categoryMarkers = {'o', 's', 'd', 'x'};
    end
    
    methods
        function obj = ScatterPlot(ieegdata, is3D)
            %SCATTERPLOT Construct an instance of this class
            %   Detailed explanation goes here
            obj.ieegdata = ieegdata;
            obj.selCh = ieegdata.plotRCh.selCh; %vyber kanalu fghjkl * pocet kanalu
            obj.selChNames = ieegdata.plotRCh.selChNames; %vyber kanalu fghjkl * pocet kanalu
            obj.dispSelChName = [];
            obj.dispSelCh = 1:size(obj.selCh,1);  % Zobrazuji vse
            
            obj.dispFilterCh = obj.ieegdata.CH.sortorder; % Vyber podle FilterChannels
            obj.connectChannels = false;
            obj.showNumbers = 0; %defaultne se zadne labels nezobrazuji
            obj.numbers = [];
            obj.markerSize = 34;
            
            if ~exist('is3D','var')
                obj.is3D = false; 
            else
                obj.is3D = is3D;
            end
            
            obj.setCategories();
            
            obj.drawScatterPlot(0.5, 0.5, 'tmax', 'valmax'); %TODO; zmenit na tmax, valmax, 0.5, 0.5
        end
        
        function drawScatterPlot(obj, valFraction, intFraction, axisX, axisY)
            obj.setTriggerValues(valFraction, intFraction);
            obj.initAxes(axisX, axisY);
            obj.updatePlot();
            obj.fixAxesLimits();
        end
        
        function PlotBrain(obj,katnum,xy,rangeZ)
            if ~exist('katnum','var') || isempty(katnum), katnum = 1; end
            if ~exist('xy','var'), xy = 'y'; end %defaultne osaY = valmax napriklad
            if ~exist('rangeZ','var') %pokud neni zadane
                rangeZ = iff(xy=='x',xlim(obj.ax),ylim(obj.ax));  %nastavi se podle limitu scatterplotu
            end 
            selChFiltered = obj.selCh(obj.dispChannels,:); %chci zobrazovat jen signif odpovedi
            iData = logical(selChFiltered(:,katnum)); %kanaly se signifikantim rozdilem vuci baseline v teto kategorii
            if(xy=='x')
                data = obj.dispData(katnum).dataX(iData);
                dataName = obj.axisX;
            else
                data = obj.dispData(katnum).dataY(iData);
                dataName = obj.axisY;
            end
            obj.ieegdata.CH.plotCh3D.selch = []; %nechci mit vybrany zadny kanal z minula
            obj.ieegdata.CH.ChannelPlot([],0,data,... %param chnvals
                obj.dispChannels(iData),... %chnsel jsou cisla kanalu, pokud chci jen jejich vyber
                [],[],{[dataName '(' obj.categoryNames{katnum} '), SelCh: ' obj.dispSelChName ], ... %popis grafu = title - prvni radek
                ['show:' obj.ieegdata.CH.plotCh2D.chshowstr]}, ... %popis grafu title, druhy radek
                rangeZ); %rozsah hodnot - meritko barevne skaly
            %set(obj.plotAUC.Eh.CH.plotCh3D.fh, 'WindowButtonDownFcn', {@obj.hybejPlot3Dclick, selch});
        end
        
        function setXYLim(obj,xrange,yrange) %set axes limit
            if ~exist('xrange','var') || isempty(xrange), xrange = xlim(obj.ax); end
            if ~exist('yrange','var') || isempty(yrange), yrange = ylim(obj.ax); end
            xlim(obj.ax,xrange);
            ylim(obj.ax,yrange);
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
 
        function initAxes(obj, axisX, axisY)
           switch axisX
                case 'valmax'
                    labelX = 'v_{max}';
                case 'tmax'
                    labelX = 't_{max}';
                case 'tfrac'
                    labelX = ['t_{' num2str(obj.valFraction) '}'];
                case 'tint'
                    labelX =  ['t_{int, ' num2str(obj.intFraction) '}'];
                otherwise
                    disp('X axis specification must be one of: valmax, tmax, tfrac, tint');
                    return;
            end
            
            switch axisY
                case 'valmax'
                    labelY = 'v_{max}';
                case 'tmax'
                    labelY = 't_{max}';
                case 'tfrac'
                    labelY = ['t_{' num2str(obj.valFraction) '}'];
                case 'tint'
                    labelY =  ['t_{int, ' num2str(obj.intFraction) '}'];
                otherwise
                    disp('Y axis specification must be one of: valmax, tmax, tfrac, tint');
                    return;
            end
            
            obj.axisX = axisX;
            obj.axisY = axisY;

            obj.fig = figure('CloseRequestFcn', @obj.tearDownFigCallback, 'Name', 'ScatterPlot');
            
            obj.ax = axes(obj.fig);
            xlabel(obj.ax, labelX);
            ylabel(obj.ax, labelY);
            zlabel(obj.ax, 'channel');

            obj.filterListener = addlistener(obj.ieegdata.CH, 'FilterChanged', @obj.filterChangedCallback);
            obj.channelListener = addlistener(obj.ieegdata, 'selectedChannel', 'PostSet', @obj.channelChangedCallback);
            
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
        
        function updatePlot(obj)
            obj.setDisplayedChannels(); % Kombinace voleb pro zobrazeni kanalu
            selChFiltered = obj.selCh(obj.dispChannels,:); %filter kanalu ve vyberu fghjkl
            if ~isempty(obj.plots), delete(obj.plots), end; obj.plots = [];
            if ~isempty(obj.sbox), delete(obj.sbox), end
            if ~isempty(obj.sbox), delete(obj.pbox), end
            if ~isempty(obj.connectionsPlot), delete(obj.connectionsPlot), end; obj.connectionsPlot = [];
            if ~isempty(obj.numbers), delete(obj.numbers), end; obj.numbers = [];      
            
            if ~isempty(obj.dispSelChName)
                obj.sbox = annotation(obj.fig, 'textbox',[0 .9 .4 .1], 'String', obj.dispSelChName, 'EdgeColor', 'none');
            end
            
            catlist = strjoin(obj.categoryNames(obj.categoriesSelectionIndex), ', ');
            obj.pbox = annotation(obj.fig, 'textbox', [0 0 .4 .1], 'String', ['C: ' catlist], 'EdgeColor', 'none');
            
            obj.stats = struct();
            if isempty(obj.dispChannels)
                disp('No channels corresponding to the selection');
                return;
            end
            
            for k = obj.categoriesSelectionIndex %1:numel(obj.categories)
                catnum = obj.categories(k);
                [obj.stats(k).valmax, obj.stats(k).tmax, obj.stats(k).tfrac, obj.stats(k).tint] = obj.ieegdata.ResponseTriggerTime(obj.valFraction, obj.intFraction, catnum, obj.dispChannels);
            end
            
            hold(obj.ax, 'on');
            legend(obj.ax, 'off');
            
            if obj.connectChannels
                obj.drawConnectChannels();
            end
            obj.drawPlot(selChFiltered);
            
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
        
        function drawPlot(obj, selChFiltered)
            for k = obj.categoriesSelectionIndex %1:numel(obj.categories)
                dataX = obj.stats(k).(obj.axisX);
                dataY = obj.stats(k).(obj.axisY);
                iData = logical(selChFiltered(:,k)); %kanaly se signifikantim rozdilem vuci baseline v teto kategorii
                if any(iData)
                    if obj.is3D
                        obj.plots(k,1) = scatter3(obj.ax, dataX(iData), dataY(iData), obj.dispChannels(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'flat', 'DisplayName', obj.categoryNames{k});
                    else
                        obj.plots(k,1) = scatter(obj.ax, dataX(iData), dataY(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'flat', 'DisplayName', obj.categoryNames{k});
                    end
                end
                iData = ~iData; %kanaly bez signif rozdilu vuci baseline v teto kategorii
                if any(iData)
                    if obj.is3D
                        obj.plots(k,2) = scatter3(obj.ax, dataX(iData), dataY(iData), obj.dispChannels(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'none', 'DisplayName', obj.categoryNames{k},...
                            'HandleVisibility','off'); %nebude v legende
                    else
                        obj.plots(k,2) = scatter(obj.ax, dataX(iData), dataY(iData), obj.markerSize, repmat(obj.baseColors(k,:), sum(iData), 1), obj.categoryMarkers{k}, 'MarkerFaceColor', 'none', 'DisplayName', obj.categoryNames{k},...
                            'HandleVisibility','off'); %nebude v legende
                    end
                end
                if obj.showNumbers > 0
                    if obj.showNumbers == 1
                        labels = cellstr(num2str(obj.dispChannels')); %cisla kanalu
                    else
                        labels = {obj.ieegdata.CH.H.channels(obj.dispChannels).name}'; %jmena kanalu
                    end
                    dx = diff(xlim)/100;
                    if obj.is3D
                        th = text(dataX+dx, dataY, obj.dispChannels, labels, 'FontSize', 8);
                    else
                        th = text(dataX+dx, dataY, labels, 'FontSize', 8);
                    end
                    set(th, 'Clipping', 'on');
                    obj.numbers = [obj.numbers th];
                end
                obj.dispData(k).dataX = dataX; %zalohuju vyobrazena data pro jine pouziti
                obj.dispData(k).dataY = dataY;
            end
        end
        
        function drawConnectChannels(obj)
        % Nakresli linku spojujici stejne kanaly. Ruzne barvy musi byt samostatny plot (aby mohl scatter zustat ve stejnych osach)
            if length(obj.categoriesSelectionIndex) > 1
                catIndex = zeros(size(obj.categoriesSelectionIndex(1)));
                x = zeros(length(obj.categoriesSelectionIndex(1)), length(obj.stats(1).(obj.axisX)));
                y = zeros(length(obj.categoriesSelectionIndex(1)), length(obj.stats(1).(obj.axisX)));
                for cat = 1:length(obj.categoriesSelectionIndex)
                    catIndex(cat) = obj.categoriesSelectionIndex(cat);
                    x(cat,:) = obj.stats(cat).(obj.axisX);
                    y(cat,:) = obj.stats(cat).(obj.axisY);
                end
                l = length(obj.stats(catIndex(1)).(obj.axisX));
                for c1 = 1:length(obj.categoriesSelectionIndex)
                    for c2 = 1:c1-1
                        for k = 1:l
                            if obj.is3D
                                z = obj.dispChannels(k);
                                obj.connectionsPlot(end+1) = plot3([x(c1,k) x(c2,k)], [y(c1,k) y(c2,k)], [z z], 'Color', [0.5 0.5 0.5], 'HandleVisibility','off');
                            else
                                obj.connectionsPlot(end+1) = plot([x(c1,k) x(c2,k)], [y(c1,k) y(c2,k)], 'Color', [0.5 0.5 0.5], 'HandleVisibility','off');
                            end
                        end
                    end
                end
            else
                disp('No categories to connect');
                obj.connectChannels = false;
            end
        end
        
        function highlightSelected(obj, ch)
            if ~isempty(obj.highlights)
                delete(obj.highlights);
            end
            obj.highlights = [];
            idx = find(obj.dispChannels == ch);
            hold(obj.ax, 'on');
            if idx
                for k = obj.categoriesSelectionIndex
                    dataX = obj.stats(k).(obj.axisX);
                    dataY = obj.stats(k).(obj.axisY);
                    if obj.is3D
                        obj.highlights(k) = scatter3(obj.ax, dataX(idx), dataY(idx), ch, 3*obj.markerSize, 0.75*obj.baseColors(k,:), 'o', 'MarkerFaceColor', 'none', 'LineWidth', 2, 'HandleVisibility','off');
                    else
                        obj.highlights(k) = scatter(obj.ax, dataX(idx), dataY(idx), 3*obj.markerSize, 0.75*obj.baseColors(k,:), 'o', 'MarkerFaceColor', 'none', 'LineWidth', 2, 'HandleVisibility','off');
                    end
                end
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
                    obj.dispFilterCh = obj.ieegdata.CH.sortorder; % Vyber podle FilterChannels
                    obj.dispSelCh = 1:size(obj.selCh,1);   % Zrusit vyber dle SelCh
                    obj.dispSelChName = [];
                    obj.updatePlot();
                case {'f','g','h','j','k','l'}
                    obj.dispSelCh = find(obj.selCh(:,'fghjkl'==eventDat.Key)');
                    obj.dispSelChName = obj.selChNames{'fghjkl'==eventDat.Key};
                    obj.updatePlot();
                case {'s'}
                    obj.connectChannels = ~obj.connectChannels;
                    obj.updatePlot();
                case {'n'}
                    obj.showNumbers = iff(obj.showNumbers==0, 1, iff(obj.showNumbers==1,2,0)); %0->1->2->0
                    obj.updatePlot();
                case {'add'}
                    obj.markerSize = obj.markerSize + 8;
                    obj.updatePlot();
                case {'subtract'}
                    obj.markerSize = max(2, obj.markerSize - 8);
                    obj.updatePlot();
            end
        end
        
        function hybejScatterPlotClick(obj,h,~)
            if isempty(obj.dispChannels) % Pokud nejsou zobrazene zadne kanaly, nedelam nic
              return;
            end

            mousept = get(gca,'currentPoint');
            p1 = mousept(1,:); p2 = mousept(2,:); % souradnice kliknuti v grafu - predni a zadni bod
            chs  = zeros(size(obj.categoriesSelectionIndex));
            dist = zeros(size(obj.categoriesSelectionIndex));
            for k = obj.categoriesSelectionIndex % vsechny zobrazene kategorie
              dataX = obj.stats(k).(obj.axisX);
              dataY = obj.stats(k).(obj.axisY);
              if obj.is3D
                  coordinates = [dataX; dataY; obj.dispChannels]; % souradnice zobrazenych kanalu
                  [chs(k), dist(k)] = findClosestPoint(p1, p2, coordinates, 0.05);    % najdu kanal nejblize mistu kliknuti
              else
                  x = p1(1); y = p1(2); % souradnice v grafu (ve 2D pouze "predni" bod)
                  [chs(k), dist(k)] = dsearchn([dataX' dataY'], [x y]); %najde nejblizsi kanal a vzdalenost k nemu
                  if dist(k) > mean([diff(ylim(obj.ax)), diff(xlim(obj.ax))])/20 % kdyz kliknu moc daleko od kanalu, nechci nic vybrat - nastavim [0 inf] stejne jako to dela funkce findClosestPoint
                      chs(k) = 0;
                      dist(k) = inf;
                  end
              end
            end

            [mindist, k_min] = min(dist); % vyberu skutecne nejblizsi kanal ze vsech kategorii

            if mindist < inf
                ch = obj.dispChannels(chs(k_min));
                %TODO: Pokud neni otevreny PlotResponseCh, nebude po otevreni znat cislo vybraneho kanalu. Lepsi by bylo pouzit proxy objekt, ktery drzi informaci o vybranem kanalu a v pripade zmeny vyberu posle signal, ktery se tak zpropaguje do vsech plotu, ktere ho potrebuji.
                obj.ieegdata.SelectChannel(ch);    % Pokud mam PlotResponseCh, updatuju zobrezene kanaly
                % Nevolam highlightSelected, protoze ten se zavola diky eventu
                figure(obj.fig); %kamil - dam do popredi scatter plot
            else
                obj.ieegdata.SelectChannel(0);   % zrusi vyber
            end
        end

        
        function setDisplayedChannels(obj)
            obj.dispChannels = intersect(obj.dispFilterCh, obj.dispSelCh);
        end
        
        function filterChangedCallback(obj,~,~)
            obj.dispFilterCh = obj.ieegdata.CH.sortorder;   % Zmena vyberu dle filtru
            obj.updatePlot();
        end

        function channelChangedCallback(obj, ~, eventData)
            obj.highlightSelected(eventData.AffectedObject.selectedChannel);
        end
        
        function tearDownFigCallback(obj,src,~)
            delete(obj.filterListener);
            delete(obj.channelListener);
            delete(src);
        end      
        
    end
    
end

