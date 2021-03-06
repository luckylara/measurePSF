function varargout=measurePSF(PSFstack,micsPerPixelXY,micsPerPixelZ,varargin)
% Display PSF and measure its size in X, Y, and Z
%
% function varargout=measurePSF(PSFstack,micsPerPixelXY,micsPerPixelZ,maxIntensityInZ)
%
% Purpose
% Fit and display a PSF. Reports FWHM to on-screen figure
% Note: currently uses two-component fits for the PSF in Z. This may be a bad choice
%       for 2-photon PSFs or PSFs which are sparsely sampled in Z. Will need to look 
%       at real data and decide what to do about the Z-fits. So far only tried simulated
%       PSFs.
%
%
% DEMO MODE - run with no input arguments
%
% INPUTS (required)
% PSFstack  - a 3-D array (imagestack). First layer should be that nearest the objective
% micsPerPixelXY - number of microns per pixel in X and Y
% micsPerPixelZ  - number of microns per pixel in Z (i.e. distance between adjacent Z planes)
%
% INPUTS (optional param/val pairs)
% maxIntensityInZ - [false by default] if true we use the max intensity projection
%                   for the Z PSFs. This is likely necessary if the PSF is very tilted.
% zFitOrder - [1 by default]. Number of gaussians to use for the fit of the Z PSF
% medFiltSize - [1 by default -- no filtering]. If more than one performs a median filtering 
%				operation on each slice with a filter of this size.
% frameSize - [false by default] If a scalar, frameSize is used to zoom into the location of the
%             the identified bead. e.g. if frameSize is 50, a 50 by 50 pixel window is centered 
%             on the bead. 
%
% OUTPUTS
% Returns fit objects and various handles (not finalised yet)
%
%
% Rob Campbell - Basel 2016
%
%
% Requires:
% Curve-Fitting Toolbox

if nargin<1
    help(mfilename)
    P=load('PSF');
    PSFstack = P.PSF;
    micsPerPixelXY=0.05;
    micsPerPixelZ=0.500;
elseif nargin<3
    fprintf('\n\n ----> Function requires three input arguments! <---- \n\n')
    help(mfilename)
    return
end



params = inputParser;
params.CaseSensitive = false;
params.addParamValue('maxIntensityInZ', 1, @(x) islogical(x) || x==0 || x==1);
params.addParamValue('zFitOrder', 1, @(x) isnumeric(x) && isscalar(x));
params.addParamValue('medFiltSize', 1, @(x) isnumeric(x) && isscalar(x));
params.addParamValue('frameSize',false, @(x) x==false || (isnumeric(x) && isscalar(x)) )

params.parse(varargin{:});

maxIntensityInZ = params.Results.maxIntensityInZ;
zFitOrder = params.Results.zFitOrder;
medFiltSize = params.Results.medFiltSize;
frameSize = params.Results.frameSize;


% Step One
%
% Estimate the slice that contains center of the PSF in Z by finding the brightest point.
PSFstack = double(PSFstack);
for ii=1:size(PSFstack,3)
	PSFstack(:,:,ii) = 	medfilt2(PSFstack(:,:,ii),[medFiltSize,medFiltSize]);
end
PSFstack = PSFstack - median(PSFstack(:)); %subtract the baseline because the Gaussian fit doesn't have an offset parameter

%Clean up the PSF because we're using max
DS = imresize(PSFstack,0.25); 
for ii=1:size(DS,3)
    DS(:,:,ii) = conv2(DS(:,:,ii),ones(2),'same');
end
Z = max(squeeze(max(DS))); 

z=max(squeeze(max(DS)));
f = measurePSF.fit_Intensity(z,1); 
psfCenterInZ = round(f.b1);

if psfCenterInZ > size(PSFstack,3) || psfCenterInZ<1
    fprintf('PSF center in Z estimated as slice %d. That is out of range. PSF stack has %d slices\n',...
        psfCenterInZ,size(PSFstack,3))
    return
end

midZ=round(size(PSFstack,3)/2); %The calculated mid-point of the PSF stack






% Step Two
%
% Find the center of the bead in X and Y by fitting gaussians along these dimensions.
% We will use these values to show cross-sections of it along X and Y at the level of the image plotted above.
% Always apply a moderate median filter to help ensure we get a reasonable fit
maxZplane = PSFstack(:,:,psfCenterInZ);
if medFiltSize==1
    maxZplaneForFit = medfilt2(maxZplane,[2,2]);
else
    maxZplaneForFit = maxZplane;
end

[psfCenterInX,psfCenterInY,badFit]=measurePSF.findPSF_centre(maxZplaneForFit);


if isnumeric(frameSize) && ~badFit %Zoom into the bead if the user asked for this
    x=(-frameSize/2 : frameSize/2)+psfCenterInX;
    y=(-frameSize/2 : frameSize/2)+psfCenterInY;
    x=round(x);
    y=round(y);

    maxZplaneForFit = maxZplaneForFit(y,x);
    maxZplane = maxZplane(y,x);
    PSFstack = PSFstack(y,x,:);

    [psfCenterInX,psfCenterInY]=measurePSF.findPSF_centre(maxZplaneForFit);

end


%Plot the mid-point of the stack
clf
s=size(PSFstack);
set(gcf,'Name',sprintf('Image size: %d x %d',s(1:2)))
%PSF at mid-point
axes('Position',[0.03,0.07,0.4,0.4])
imagesc(maxZplane)

text(size(PSFstack,1)*0.025,...
    size(PSFstack,2)*0.04,...
    sprintf('PSF center at slice #%d',psfCenterInZ),...
    'color','w','VerticalAlignment','top') 


%Optionally, show the axes. Right now, I don't think we want this at all so it's not an input argument 
showAxesInMainPSFplot=0;
if showAxesInMainPSFplot
    Xtick = linspace(1,size(maxZplane,1),8);
    Ytick = linspace(1,size(maxZplane,2),8);
    set(gca,'XTick',Xtick,'XTickLabel',measurePSF.round(Xtick*micsPerPixelXY,2),...
            'YTick',Ytick,'YTickLabel',measurePSF.round(Ytick*micsPerPixelXY,2));
else
    set(gca,'XTick',[],'YTick',[])
end


%Add lines to the main X/Y plot showing where we are slicing it to take the cross-sections
hold on
plot(xlim,[psfCenterInY,psfCenterInY],'--w')
plot([psfCenterInX,psfCenterInX],ylim,'--w')
hold off


%The cross-section sliced along the rows (the fit shown along the right side of the X/Y PSF)
axes('Position',[0.435,0.07,0.1,0.4])
yvals = maxZplane(:,psfCenterInX);
x=(1:length(yvals))*micsPerPixelXY;
fitX = measurePSF.fit_Intensity(yvals,micsPerPixelXY,1);
measurePSF.plotCrossSectionAndFit(x,yvals,fitX,micsPerPixelXY/2,1);
X.xVals=x;
X.yVals=yvals;
set(gca,'XTickLabel',[])


%The cross-section sliced down the columns (fit shown above the X/Y PSF)
axes('Position',[0.03,0.475,0.4,0.1])
yvals = maxZplane(psfCenterInY,:);
x=(1:length(yvals))*micsPerPixelXY;
fitY = measurePSF.fit_Intensity(yvals,micsPerPixelXY);
measurePSF.plotCrossSectionAndFit(x,yvals,fitY,micsPerPixelXY/2);
Y.xVals=x;
Y.yVals=yvals;
set(gca,'XTickLabel',[])



% Step Three
%
% We now obtain images showing the PSF's extent in Z
% We do this by taking maximum intensity projections or slices through the maximum
axes('Position',[0.03,0.6,0.4,0.25])


%PSF in Z/X (panel above)
if maxIntensityInZ
    PSF_ZX=squeeze(max(PSFstack,[],1));
else
    PSF_ZX=squeeze(PSFstack(psfCenterInY,:,:));
end

imagesc(PSF_ZX)

Ytick = linspace(1,size(PSF_ZX,1),3);
set(gca,'XAxisLocation','Top',...
        'XTick',[],...
        'YTick',Ytick,'YTickLabel',measurePSF.round(Ytick*micsPerPixelXY,2));

text(1,1,sprintf('PSF in Z/X'), 'Color','w','VerticalAlignment','top');

%This is the fitted Z/Y PSF with the FWHM
axes('Position',[0.03,0.85,0.4,0.1])
maxPSF_ZX = max(PSF_ZX,[],1);
baseline = sort(maxPSF_ZX);
baseline = mean(baseline(1:5));
maxPSF_ZX = maxPSF_ZX-baseline;

fitZX = measurePSF.fit_Intensity(maxPSF_ZX, micsPerPixelZ,zFitOrder);
x = (1:length(maxPSF_ZX))*micsPerPixelZ;
[OUT.ZX.FWHM,OUT.ZX.fitPlot_H] = measurePSF.plotCrossSectionAndFit(x,maxPSF_ZX,fitZX,micsPerPixelZ/4);
set(gca,'XAxisLocation','Top')




%PSF in Z/Y (panel on the right on the right)
axes('Position',[0.56,0.07,0.25,0.4])
if maxIntensityInZ
    PSF_ZY=squeeze(max(PSFstack,[],2));
else
    PSF_ZY=squeeze(PSFstack(:,psfCenterInX,:));
end

PSF_ZY=rot90(PSF_ZY,3);
imagesc(PSF_ZY)

Xtick = linspace(1,size(PSF_ZY,2),3);
set(gca,'YAxisLocation','Right',...
        'XTick',Xtick,'XTickLabel',measurePSF.round(Xtick*micsPerPixelXY,2),...
        'YTick',[])

text(1,1,sprintf('PSF in Z/Y'), 'Color','w','VerticalAlignment','top');

%This is the fitted Z/X PSF with the FWHM
axes('Position',[0.8,0.07,0.1,0.4])
maxPSF_ZY = max(PSF_ZY,[],2);
baseline = sort(maxPSF_ZY);
baseline = mean(baseline(1:5));
maxPSF_ZY = maxPSF_ZY-baseline;

fitZY = measurePSF.fit_Intensity(maxPSF_ZY, micsPerPixelZ,zFitOrder);
x = (1:length(maxPSF_ZY))*micsPerPixelZ;
[OUT.ZY.FWHM, OUT.ZY.fitPlot_H] = measurePSF.plotCrossSectionAndFit(x,maxPSF_ZY,fitZY,micsPerPixelZ/4,1);
set(gca,'XAxisLocation','Top')



% Step Four
%
% Finally, we add a plot with a scroll-bar so we can view the PSF as desires
axes('Position',[0.5,0.55,0.4,0.4])
userSelected=imagesc(maxZplane);
set(userSelected,'Tag','userSelected')
box on
set(gca,'XTick',[],'YTick',[])

slider = uicontrol('Style','Slider', ...
            'Units','normalized',...
            'Position',[0.9,0.55,0.02,0.4],...
            'Min',1,...
            'Max',size(PSFstack,3),...
            'Value',psfCenterInZ,...
            'Tag','DepthSlider',...
            'Callback', @(~,~) updateUserSelected(PSFstack,psfCenterInZ,micsPerPixelZ) ) ;

title(sprintf('Slice #%d',psfCenterInZ))


if nargout>0
    OUT.slider = slider;
    OUT.Y.fit  = fitY;
    OUT.Y.data  = Y;
    OUT.X.fit  = fitX;
    OUT.X.data  = X;
    OUT.ZY.fit = fitZY;
    OUT.ZX.fit = fitZY;
    OUT.ZX.im = PSF_ZX;
    OUT.ZY.im = PSF_ZY;
    varargout{1} = OUT;
end


%-----------------------------------------------------------------------------
function updateUserSelected(PSFstack,psfCenterInZ,micsPerPixelZ)
    % Runs when the user moves the slider
    Hax=findobj('Tag','userSelected');
    Hslider = findobj('Tag','DepthSlider');

    thisSlice = round(get(Hslider,'Value'));
    set(Hax,'CData',PSFstack(:,:,thisSlice))

    caxis([min(PSFstack(:)), max(PSFstack(:))])

    title(sprintf('Slice #%d %0.2f \\mum', thisSlice, (psfCenterInZ-thisSlice)*micsPerPixelZ ))

